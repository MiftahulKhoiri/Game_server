package store

import (
	"context"
	"database/sql"
	"encoding/json"
	"errors"
	"fmt"
	"time"

	"github.com/MiftahulKhoiri/Game_server/internal/game"
)

// Perdagangan antarpemain (roadmap no. 176, 182-185). Setiap langkah berjalan dalam SATU transaksi
// SQLite yang mengubah kedua pemain sekaligus, jadi barang/emas tidak bisa terduplikasi atau hilang
// bila dua permintaan datang bersamaan (koneksi tunggal = transaksi bergantian).

// Kesalahan perdagangan.
var (
	ErrTradeSelf     = errors.New("tidak bisa berdagang dengan diri sendiri")
	ErrTradeNoPlayer = errors.New("pemain tujuan tidak ditemukan")
	ErrTradeNotFound = errors.New("tawaran tidak ditemukan atau sudah selesai")
	ErrTradeTooMany  = fmt.Errorf("maksimal %d tawaran yang belum selesai", game.MaxOpenTrades)
	ErrTradeBattle   = errors.New("tidak bisa berdagang saat bertarung")
)

const tradeCols = `t.id, t.from_id, t.to_id, f.name, o.name, t.item, t.qty, t.price, t.status, t.created_at`

const tradeFrom = ` FROM trades t JOIN players f ON f.id = t.from_id JOIN players o ON o.id = t.to_id`

func scanTrade(row rowScanner) (game.Trade, error) {
	var t game.Trade
	err := row.Scan(&t.ID, &t.FromID, &t.ToID, &t.FromName, &t.ToName, &t.Item, &t.Qty, &t.Price, &t.Status, &t.Created)
	if errors.Is(err, sql.ErrNoRows) {
		return t, ErrTradeNotFound
	}
	return t, err
}

// Trades: tawaran masuk dan keluar milik pemain: semua yang pending lalu 10 terakhir yang sudah selesai.
func (s *Store) Trades(ctx context.Context, playerID string) ([]game.Trade, error) {
	rows, err := s.db.QueryContext(ctx, `SELECT `+tradeCols+tradeFrom+`
		WHERE (t.from_id = ?1 OR t.to_id = ?1) AND (t.status = 'pending' OR t.id IN (
			SELECT id FROM trades WHERE (from_id = ?1 OR to_id = ?1) AND status != 'pending' ORDER BY updated_at DESC, id DESC LIMIT 10))
		ORDER BY t.status != 'pending', t.id DESC`, playerID)
	if err != nil {
		return nil, fmt.Errorf("baca tawaran: %w", err)
	}
	defer rows.Close()
	out := []game.Trade{}
	for rows.Next() {
		t, err := scanTrade(rows)
		if err != nil {
			return nil, err
		}
		out = append(out, t)
	}
	return out, rows.Err()
}

// pair memuat dua pemain di dalam tx, menjalankan fn, memeriksa batas ekonomi keduanya, lalu menyimpan.
func pairUpdate(ctx context.Context, tx *sql.Tx, aID, bID string, fn func(a, b *game.Player) error) (game.Player, error) {
	a, err := scanPlayer(tx.QueryRowContext(ctx, selectPlayer+` WHERE id = ?`, aID))
	if err != nil {
		return game.Player{}, err
	}
	b, err := scanPlayer(tx.QueryRowContext(ctx, selectPlayer+` WHERE id = ?`, bID))
	if err != nil {
		return game.Player{}, err
	}
	if err := fn(&a, &b); err != nil {
		return game.Player{}, err
	}
	stamp := time.Now().UTC().Format(time.RFC3339Nano)
	for _, p := range []*game.Player{&a, &b} {
		if err := p.State.ValidEconomy(); err != nil {
			return game.Player{}, fmt.Errorf("%w: %v", ErrInvalidState, err)
		}
		js, err := json.Marshal(p.State)
		if err != nil {
			return game.Player{}, err
		}
		if _, err := tx.ExecContext(ctx, `UPDATE players SET state = ?, version = version + 1, updated_at = ? WHERE id = ?`,
			string(js), stamp, p.ID); err != nil {
			return game.Player{}, fmt.Errorf("simpan pemain: %w", err)
		}
		p.Version++
	}
	return a, nil
}

func inBattle(ctx context.Context, tx *sql.Tx, id string) bool {
	_, err := loadBattle(ctx, tx, id)
	return err == nil
}

// CreateTrade: pemain fromID menawarkan qty barang kepada pemain bernama toName seharga price emas.
// Barangnya langsung dititipkan (keluar dari ransel penjual). Mengembalikan state penjual terbaru.
func (s *Store) CreateTrade(ctx context.Context, fromID, toName, item string, qty, price int) (game.Player, error) {
	tx, err := s.db.BeginTx(ctx, nil)
	if err != nil {
		return game.Player{}, err
	}
	defer tx.Rollback()
	var toID, realName string
	err = tx.QueryRowContext(ctx, `SELECT id, name FROM players WHERE name = ?`, toName).Scan(&toID, &realName)
	if errors.Is(err, sql.ErrNoRows) {
		return game.Player{}, ErrTradeNoPlayer
	}
	if err != nil {
		return game.Player{}, err
	}
	if toID == fromID {
		return game.Player{}, ErrTradeSelf
	}
	if inBattle(ctx, tx, fromID) {
		return game.Player{}, ErrTradeBattle
	}
	var open int
	if err := tx.QueryRowContext(ctx, `SELECT COUNT(*) FROM trades WHERE from_id = ? AND status = 'pending'`, fromID).Scan(&open); err != nil {
		return game.Player{}, err
	}
	if open >= game.MaxOpenTrades {
		return game.Player{}, ErrTradeTooMany
	}
	seller, err := pairUpdate(ctx, tx, fromID, toID, func(a, _ *game.Player) error {
		return a.State.EscrowTrade(item, qty, price, realName)
	})
	if err != nil {
		return game.Player{}, err
	}
	now := time.Now().Unix()
	if _, err := tx.ExecContext(ctx, `INSERT INTO trades (from_id, to_id, item, qty, price, status, created_at, updated_at)
		VALUES (?, ?, ?, ?, ?, 'pending', ?, ?)`, fromID, toID, item, qty, price, now, now); err != nil {
		return game.Player{}, fmt.Errorf("simpan tawaran: %w", err)
	}
	return seller, tx.Commit()
}

// AcceptTrade: pembeli (playerID = penerima tawaran) membayar dan menerima barang.
func (s *Store) AcceptTrade(ctx context.Context, playerID string, tradeID int64) (game.Player, error) {
	return s.finishTrade(ctx, playerID, tradeID, game.TradeDone)
}

// CancelTrade: penjual membatalkan, atau penerima menolak; barang kembali ke penjual.
func (s *Store) CancelTrade(ctx context.Context, playerID string, tradeID int64) (game.Player, error) {
	return s.finishTrade(ctx, playerID, tradeID, "")
}

func (s *Store) finishTrade(ctx context.Context, playerID string, tradeID int64, want string) (game.Player, error) {
	tx, err := s.db.BeginTx(ctx, nil)
	if err != nil {
		return game.Player{}, err
	}
	defer tx.Rollback()
	t, err := scanTrade(tx.QueryRowContext(ctx, `SELECT `+tradeCols+tradeFrom+` WHERE t.id = ? AND t.status = 'pending'`, tradeID))
	if err != nil {
		return game.Player{}, err
	}
	status := want
	switch {
	case want == game.TradeDone && t.ToID != playerID:
		return game.Player{}, ErrTradeNotFound // hanya penerima yang bisa membeli
	case want == "" && t.FromID == playerID:
		status = game.TradeCancelled
	case want == "" && t.ToID == playerID:
		status = game.TradeDeclined
	case want == "":
		return game.Player{}, ErrTradeNotFound
	}
	if inBattle(ctx, tx, playerID) {
		return game.Player{}, ErrTradeBattle
	}
	other := t.FromID
	if playerID == t.FromID {
		other = t.ToID
	}
	me, err := pairUpdate(ctx, tx, playerID, other, func(me, o *game.Player) error {
		seller, buyer := o, me
		if me.ID == t.FromID {
			seller, buyer = me, o
		}
		if status == game.TradeDone {
			if err := buyer.State.TradeBuy(t); err != nil {
				return err
			}
			return seller.State.TradeSold(t)
		}
		return seller.State.TradeReturn(t)
	})
	if err != nil {
		return game.Player{}, err
	}
	res, err := tx.ExecContext(ctx, `UPDATE trades SET status = ?, updated_at = ? WHERE id = ? AND status = 'pending'`,
		status, time.Now().Unix(), tradeID)
	if err != nil {
		return game.Player{}, err
	}
	if n, _ := res.RowsAffected(); n != 1 {
		return game.Player{}, ErrTradeNotFound
	}
	return me, tx.Commit()
}
