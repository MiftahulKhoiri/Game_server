package api

import (
	"errors"
	"net/http"

	"github.com/MiftahulKhoiri/Game_server/internal/game"
	"github.com/MiftahulKhoiri/Game_server/internal/store"
)

// Ekonomi (roadmap no. 171-185): bank, peti simpan, dan perdagangan antarpemain.

type amountRequest struct {
	Amount int `json:"amount"`
}

type stackRequest struct {
	Item string `json:"item"`
	Qty  int    `json:"qty"`
}

type offerRequest struct {
	To    string `json:"to"`
	Item  string `json:"item"`
	Qty   int    `json:"qty"`
	Price int    `json:"price"`
}

type tradeIDRequest struct {
	ID int64 `json:"id"`
}

func (s *Server) bankAction(deposit bool) http.HandlerFunc {
	return func(w http.ResponseWriter, r *http.Request) {
		var req amountRequest
		if !decode(w, r, &req) {
			return
		}
		s.applyToState(w, r, func(st *game.State) error {
			if deposit {
				return st.BankDeposit(req.Amount)
			}
			return st.BankWithdraw(req.Amount)
		})
	}
}

func (s *Server) storageAction(put bool) http.HandlerFunc {
	return func(w http.ResponseWriter, r *http.Request) {
		var req stackRequest
		if !decode(w, r, &req) {
			return
		}
		s.applyToState(w, r, func(st *game.State) error {
			if put {
				return st.StoragePut(req.Item, req.Qty)
			}
			return st.StorageTake(req.Item, req.Qty)
		})
	}
}

func (s *Server) listTrades(w http.ResponseWriter, r *http.Request) {
	list, err := s.store.Trades(r.Context(), playerFrom(r).ID)
	if err != nil {
		s.fail(w, r, err)
		return
	}
	writeJSON(w, http.StatusOK, map[string]any{"trades": list})
}

func (s *Server) createTrade(w http.ResponseWriter, r *http.Request) {
	var req offerRequest
	if !decode(w, r, &req) {
		return
	}
	p, err := s.store.CreateTrade(r.Context(), playerFrom(r).ID, req.To, req.Item, req.Qty, req.Price)
	s.tradeReply(w, r, p, err, http.StatusCreated)
}

func (s *Server) finishTrade(accept bool) http.HandlerFunc {
	return func(w http.ResponseWriter, r *http.Request) {
		var req tradeIDRequest
		if !decode(w, r, &req) {
			return
		}
		var p game.Player
		var err error
		if accept {
			p, err = s.store.AcceptTrade(r.Context(), playerFrom(r).ID, req.ID)
		} else {
			p, err = s.store.CancelTrade(r.Context(), playerFrom(r).ID, req.ID)
		}
		s.tradeReply(w, r, p, err, http.StatusOK)
	}
}

func (s *Server) tradeReply(w http.ResponseWriter, r *http.Request, p game.Player, err error, ok int) {
	switch {
	case err == nil:
		writeJSON(w, ok, p)
	case errors.Is(err, store.ErrTradeNoPlayer), errors.Is(err, store.ErrTradeNotFound), errors.Is(err, game.ErrUnknownItem):
		writeError(w, http.StatusNotFound, err.Error())
	case errors.Is(err, store.ErrTradeBattle):
		writeError(w, http.StatusConflict, err.Error())
	case errors.Is(err, store.ErrTradeSelf), errors.Is(err, store.ErrTradeTooMany), isRuleError(err):
		writeError(w, http.StatusUnprocessableEntity, err.Error())
	default:
		s.fail(w, r, err)
	}
}
