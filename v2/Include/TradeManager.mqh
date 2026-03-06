//+------------------------------------------------------------------+
//|                                              TradeManager.mqh   |
//|      Institutional EA v2 — Fast Execution + Position Mgmt      |
//|  Tick-based entry (market order fires instantly on touch).      |
//|  3-phase adaptive ATR trailing SL. Partial exits. Float watch. |
//+------------------------------------------------------------------+
#ifndef TRADEMANAGER_V2_MQH
#define TRADEMANAGER_V2_MQH

#include "Defines.mqh"
#include <Trade\Trade.mqh>
#include <Trade\PositionInfo.mqh>
#include <Trade\OrderInfo.mqh>

class CTradeManager {
private:
   CTrade        m_trade;
   CPositionInfo m_pos;
   COrderInfo    m_ord;

   int    m_slippage;
   bool   m_useBreakeven;
   bool   m_usePartial;
   bool   m_useTrail;
   ulong  m_magic;

   //--- Pending limit orders tracking
   struct SPendingOrder {
      string   symbol;
      ulong    ticket;
      datetime placedTime;
      double   entry, sl, tp;
      bool     active;
   };
   SPendingOrder m_pending[];
   int           m_pendingCount;

   //--- Per-position management state (INDEX-BASED — no struct pointers)
   ulong          m_mgmtTicket[];
   bool           m_mgmtP1Done[];
   bool           m_mgmtP2Done[];
   int            m_mgmtTrailPhase[];  // 0=NONE,1=P1,2=P2,3=P3
   int            m_mgmtCount;

   //-----------------------------------------------------------
   ENUM_ORDER_TYPE_FILLING GetFilling(string sym) {
      long mode = SymbolInfoInteger(sym, SYMBOL_FILLING_MODE);
      if((mode & SYMBOL_FILLING_FOK) != 0) return ORDER_FILLING_FOK;
      if((mode & SYMBOL_FILLING_IOC) != 0) return ORDER_FILLING_IOC;
      return ORDER_FILLING_RETURN;
   }

   void SetupForSymbol(string sym) {
      m_trade.SetExpertMagicNumber(m_magic);
      m_trade.SetDeviationInPoints(m_slippage);
      m_trade.SetTypeFilling(GetFilling(sym));
   }

   bool IsOurPos(ulong ticket) {
      if(!m_pos.SelectByTicket(ticket)) return false;
      return (m_pos.Magic() == m_magic);
   }
   bool IsOurOrder(ulong ticket) {
      if(!OrderSelect(ticket)) return false;
      return ((ulong)OrderGetInteger(ORDER_MAGIC) == m_magic);
   }

   void AddPending(string sym, ulong t, double e, double sl, double tp) {
      if(m_pendingCount >= ArraySize(m_pending))
         ArrayResize(m_pending, m_pendingCount + 10);
      m_pending[m_pendingCount].symbol     = sym;
      m_pending[m_pendingCount].ticket     = t;
      m_pending[m_pendingCount].placedTime = TimeCurrent();
      m_pending[m_pendingCount].entry      = e;
      m_pending[m_pendingCount].sl         = sl;
      m_pending[m_pendingCount].tp         = tp;
      m_pending[m_pendingCount].active     = true;
      m_pendingCount++;
   }

   //--- Return index of mgmt slot for ticket, or -1 if not found
   int FindMgmtIdx(ulong ticket) {
      for(int i = 0; i < m_mgmtCount; i++)
         if(m_mgmtTicket[i] == ticket) return i;
      return -1;
   }

   //--- Ensure mgmt slot exists; return index
   int EnsureMgmtIdx(ulong ticket) {
      int idx = FindMgmtIdx(ticket);
      if(idx >= 0) return idx;
      if(m_mgmtCount >= ArraySize(m_mgmtTicket)) {
         int newSz = m_mgmtCount + 10;
         ArrayResize(m_mgmtTicket,      newSz);
         ArrayResize(m_mgmtP1Done,      newSz);
         ArrayResize(m_mgmtP2Done,      newSz);
         ArrayResize(m_mgmtTrailPhase,  newSz);
      }
      m_mgmtTicket[m_mgmtCount]     = ticket;
      m_mgmtP1Done[m_mgmtCount]     = false;
      m_mgmtP2Done[m_mgmtCount]     = false;
      m_mgmtTrailPhase[m_mgmtCount] = 0; // TRAIL_NONE
      return m_mgmtCount++;
   }

   double GetATR(string sym, ENUM_TIMEFRAMES tf, int period = 14) {
      double buf[];
      ArraySetAsSeries(buf, true);
      int h = iATR(sym, tf, period);
      if(h == INVALID_HANDLE) return 0;
      int c = CopyBuffer(h, 0, 1, 3, buf);
      IndicatorRelease(h);
      return (c >= 1) ? buf[0] : 0;
   }

public:
   CTradeManager(int slippage = 10, bool useBreakeven = true,
                 bool usePartial = true, bool useTrail = true,
                 ulong magic = MAGIC_NUMBER_V2) {
      m_slippage     = slippage;
      m_useBreakeven = useBreakeven;
      m_usePartial   = usePartial;
      m_useTrail     = useTrail;
      m_magic        = magic;

      m_trade.SetExpertMagicNumber(magic);
      m_trade.SetDeviationInPoints(slippage);

      m_pendingCount = 0;
      ArrayResize(m_pending, 30);

      m_mgmtCount = 0;
      ArrayResize(m_mgmtTicket,     30);
      ArrayResize(m_mgmtP1Done,     30);
      ArrayResize(m_mgmtP2Done,     30);
      ArrayResize(m_mgmtTrailPhase, 30);
   }

   //-----------------------------------------------------------
   // FAST MARKET ORDER (preferred)
   //-----------------------------------------------------------
   bool PlaceMarketBuy(string sym, double sl, double tp, double lot) {
      SetupForSymbol(sym);
      bool ok = m_trade.Buy(lot, sym, 0, sl, tp, "INST_BUY");
      if(!ok) {
         Print("[Trade] BUY MKT FAIL ", sym, " err=", GetLastError(),
               " ret=", m_trade.ResultRetcode());
      } else {
         ulong ticket = m_trade.ResultOrder();
         if(ticket > 0) EnsureMgmtIdx(ticket);
         Print("[Trade] BUY MKT ", sym, " lot=", DoubleToString(lot,2),
               " SL=", DoubleToString(sl,5), " TP=", DoubleToString(tp,5));
      }
      return ok;
   }

   bool PlaceMarketSell(string sym, double sl, double tp, double lot) {
      SetupForSymbol(sym);
      bool ok = m_trade.Sell(lot, sym, 0, sl, tp, "INST_SELL");
      if(!ok) {
         Print("[Trade] SELL MKT FAIL ", sym, " err=", GetLastError(),
               " ret=", m_trade.ResultRetcode());
      } else {
         ulong ticket = m_trade.ResultOrder();
         if(ticket > 0) EnsureMgmtIdx(ticket);
         Print("[Trade] SELL MKT ", sym, " lot=", DoubleToString(lot,2),
               " SL=", DoubleToString(sl,5), " TP=", DoubleToString(tp,5));
      }
      return ok;
   }

   //-----------------------------------------------------------
   // LIMIT ORDERS
   //-----------------------------------------------------------
   bool PlaceBuyLimit(string sym, double entry, double sl, double tp, double lot) {
      SetupForSymbol(sym);
      int digits = (int)SymbolInfoInteger(sym, SYMBOL_DIGITS);
      entry = NormalizeDouble(entry, digits);
      sl    = NormalizeDouble(sl, digits);
      tp    = NormalizeDouble(tp, digits);

      double ask = SymbolInfoDouble(sym, SYMBOL_ASK);
      double pt  = SymbolInfoDouble(sym, SYMBOL_POINT);
      if(ask <= entry + pt * ENTRY_TOLERANCE_PTS)
         return PlaceMarketBuy(sym, sl, tp, lot);

      bool ok = m_trade.BuyLimit(lot, entry, sym, sl, tp, ORDER_TIME_GTC, 0, "INST_BUY_LIM");
      if(!ok) {
         uint rc = m_trade.ResultRetcode();
         Print("[Trade] BUY LIM FAIL ", sym, " rc=", rc);
         if(rc == 10016 || rc == 10015 || rc == 10014)
            return PlaceMarketBuy(sym, sl, tp, lot);
         return false;
      }
      AddPending(sym, m_trade.ResultOrder(), entry, sl, tp);
      return true;
   }

   bool PlaceSellLimit(string sym, double entry, double sl, double tp, double lot) {
      SetupForSymbol(sym);
      int digits = (int)SymbolInfoInteger(sym, SYMBOL_DIGITS);
      entry = NormalizeDouble(entry, digits);
      sl    = NormalizeDouble(sl, digits);
      tp    = NormalizeDouble(tp, digits);

      double bid = SymbolInfoDouble(sym, SYMBOL_BID);
      double pt  = SymbolInfoDouble(sym, SYMBOL_POINT);
      if(bid >= entry - pt * ENTRY_TOLERANCE_PTS)
         return PlaceMarketSell(sym, sl, tp, lot);

      bool ok = m_trade.SellLimit(lot, entry, sym, sl, tp, ORDER_TIME_GTC, 0, "INST_SELL_LIM");
      if(!ok) {
         uint rc = m_trade.ResultRetcode();
         Print("[Trade] SELL LIM FAIL ", sym, " rc=", rc);
         if(rc == 10016 || rc == 10015 || rc == 10014)
            return PlaceMarketSell(sym, sl, tp, lot);
         return false;
      }
      AddPending(sym, m_trade.ResultOrder(), entry, sl, tp);
      return true;
   }

   //-----------------------------------------------------------
   // FAST TICK-BASED ENTRY CHECK
   //-----------------------------------------------------------
   bool CheckTickEntry(string sym, ENUM_SIGNAL_DIR dir, double entryPrice,
                       double sl, double tp, double lot) {
      int    digits = (int)SymbolInfoInteger(sym, SYMBOL_DIGITS);
      double pt     = SymbolInfoDouble(sym, SYMBOL_POINT);
      double tol    = pt * ENTRY_TOLERANCE_PTS;

      if(dir == DIR_BUY) {
         double ask = SymbolInfoDouble(sym, SYMBOL_ASK);
         if(ask <= entryPrice + tol && ask >= entryPrice - tol * 4)
            return PlaceMarketBuy(sym, NormalizeDouble(sl, digits),
                                      NormalizeDouble(tp, digits), lot);
      } else if(dir == DIR_SELL) {
         double bid = SymbolInfoDouble(sym, SYMBOL_BID);
         if(bid >= entryPrice - tol && bid <= entryPrice + tol * 4)
            return PlaceMarketSell(sym, NormalizeDouble(sl, digits),
                                        NormalizeDouble(tp, digits), lot);
      }
      return false;
   }

   //-----------------------------------------------------------
   // MANAGE OPEN POSITIONS — call every tick
   //-----------------------------------------------------------
   void ManagePositions() {
      int total = PositionsTotal();
      for(int i = total - 1; i >= 0; i--) {
         ulong ticket = PositionGetTicket(i);
         if(ticket == 0 || !IsOurPos(ticket)) continue;

         string sym   = m_pos.Symbol();
         double openP = m_pos.PriceOpen();
         double sl    = m_pos.StopLoss();
         double tp    = m_pos.TakeProfit();
         double lots  = m_pos.Volume();
         int digits   = (int)SymbolInfoInteger(sym, SYMBOL_DIGITS);
         double pt    = SymbolInfoDouble(sym, SYMBOL_POINT);
         bool isBuy   = (m_pos.PositionType() == POSITION_TYPE_BUY);

         double bid   = SymbolInfoDouble(sym, SYMBOL_BID);
         double ask   = SymbolInfoDouble(sym, SYMBOL_ASK);
         double curP  = isBuy ? bid : ask;

         double slDist = MathAbs(openP - sl);
         if(slDist <= 0) continue;

         double profit = isBuy ? (curP - openP) : (openP - curP);
         double rMult  = profit / slDist;

         SetupForSymbol(sym);

         // Get or create management slot
         int mi = EnsureMgmtIdx(ticket);

         //── BREAKEVEN at 1.0R ──────────────────────────────
         if(m_useBreakeven && rMult >= BE_R_TRIGGER) {
            double beBuffer = pt * 5;
            double newSL = isBuy ? NormalizeDouble(openP + beBuffer, digits)
                                 : NormalizeDouble(openP - beBuffer, digits);
            bool alreadyBE = isBuy ? (sl >= openP) : (sl <= openP);
            if(!alreadyBE) {
               if(m_trade.PositionModify(ticket, newSL, tp))
                  Print("[Trade] BE @", DoubleToString(rMult,1), "R: ", sym,
                        " SL->", DoubleToString(newSL, digits));
            }
         }

         //── PARTIAL 1 at 2R — close 30% ────────────────────
         if(m_usePartial && rMult >= PARTIAL1_R && !m_mgmtP1Done[mi]) {
            double minLot  = SymbolInfoDouble(sym, SYMBOL_VOLUME_MIN);
            double lotStep = SymbolInfoDouble(sym, SYMBOL_VOLUME_STEP);
            if(lotStep <= 0) lotStep = 0.01;
            double closeLots = MathFloor((lots * PARTIAL1_PCT) / lotStep) * lotStep;
            if(closeLots < minLot) closeLots = minLot;
            if(closeLots < lots) {
               if(m_trade.PositionClosePartial(ticket, closeLots)) {
                  m_mgmtP1Done[mi] = true;
                  Print("[Trade] PARTIAL1 30% @", DoubleToString(rMult,1), "R: ", sym,
                        " closed=", DoubleToString(closeLots,2));
               }
            }
         }

         //── PARTIAL 2 at 3R — close another 30% ────────────
         if(m_usePartial && rMult >= PARTIAL2_R && !m_mgmtP2Done[mi]) {
            double minLot  = SymbolInfoDouble(sym, SYMBOL_VOLUME_MIN);
            double lotStep = SymbolInfoDouble(sym, SYMBOL_VOLUME_STEP);
            if(lotStep <= 0) lotStep = 0.01;
            double closeLots = MathFloor((lots * PARTIAL2_PCT) / lotStep) * lotStep;
            if(closeLots < minLot) closeLots = minLot;
            if(closeLots < lots) {
               if(m_trade.PositionClosePartial(ticket, closeLots)) {
                  m_mgmtP2Done[mi] = true;
                  Print("[Trade] PARTIAL2 30% @", DoubleToString(rMult,1), "R: ", sym,
                        " closed=", DoubleToString(closeLots,2));
               }
            }
         }

         //── 3-PHASE ADAPTIVE TRAILING SL ──────────────────
         if(m_useTrail && rMult >= TRAIL_P1_START_R) {
            double atr = GetATR(sym, PERIOD_M5, 14);
            if(atr <= 0) atr = slDist;

            double trailDist;
            int    newPhase;

            if(rMult >= TRAIL_P3_START_R) {
               trailDist = atr * TRAIL_P3_ATR_MULT;
               newPhase  = 3;
            } else if(rMult >= TRAIL_P2_START_R) {
               trailDist = atr * TRAIL_P2_ATR_MULT;
               newPhase  = 2;
            } else {
               trailDist = atr * TRAIL_P1_ATR_MULT;
               newPhase  = 1;
            }

            if(newPhase != m_mgmtTrailPhase[mi])
               Print("[Trade] Trail Phase->P", newPhase, " @", DoubleToString(rMult,1), "R: ", sym);
            m_mgmtTrailPhase[mi] = newPhase;

            double newSL;
            bool   doTrail = false;
            if(isBuy) {
               newSL   = NormalizeDouble(curP - trailDist, digits);
               doTrail = (newSL > sl + pt);
            } else {
               newSL   = NormalizeDouble(curP + trailDist, digits);
               doTrail = (newSL < sl - pt);
            }

            if(doTrail) {
               if(m_trade.PositionModify(ticket, newSL, tp))
                  Print("[Trade] Trail P", newPhase, " @", DoubleToString(rMult,1),
                        "R: ", sym, " SL->", DoubleToString(newSL, digits));
            }
         }

         //── FLOATING LOSS GUARD ──────────────────────────────
         double floatPnL  = m_pos.Profit() + m_pos.Swap();
         double tickVal   = SymbolInfoDouble(sym, SYMBOL_TRADE_TICK_VALUE);
         double tickSize  = SymbolInfoDouble(sym, SYMBOL_TRADE_TICK_SIZE);
         if(tickSize > 0 && tickVal > 0) {
            double initRisk = (slDist / tickSize) * tickVal * lots;
            if(floatPnL < -(initRisk * 2.0)) {
               Print("[Trade] Float guard! ", sym, " P&L=$", DoubleToString(floatPnL,2));
               m_trade.PositionClose(ticket);
            }
         }
      }
   }

   //-----------------------------------------------------------
   // CANCEL STALE LIMIT ORDERS
   //-----------------------------------------------------------
   void CancelStaleLimits(int timeoutMin = 20) {
      for(int i = m_pendingCount - 1; i >= 0; i--) {
         if(!m_pending[i].active) continue;
         int age = (int)((TimeCurrent() - m_pending[i].placedTime) / 60);
         if(age < timeoutMin) continue;
         if(IsOurOrder(m_pending[i].ticket)) {
            SetupForSymbol(m_pending[i].symbol);
            m_trade.OrderDelete(m_pending[i].ticket);
            Print("[Trade] Stale limit cancelled: ", m_pending[i].symbol, " age=", age, "min");
         }
         m_pending[i].active = false;
      }
      for(int i = OrdersTotal() - 1; i >= 0; i--) {
         ulong t = OrderGetTicket(i);
         if(t == 0 || !OrderSelect(t)) continue;
         if((ulong)OrderGetInteger(ORDER_MAGIC) != m_magic) continue;
         int age = (int)((TimeCurrent() - (datetime)OrderGetInteger(ORDER_TIME_SETUP)) / 60);
         if(age >= timeoutMin) {
            SetupForSymbol(OrderGetString(ORDER_SYMBOL));
            m_trade.OrderDelete(t);
         }
      }
   }

   //-----------------------------------------------------------
   // CLOSE ALL (called on daily loss cap breach)
   //-----------------------------------------------------------
   void CloseAll() {
      for(int i = PositionsTotal() - 1; i >= 0; i--) {
         ulong t = PositionGetTicket(i);
         if(t == 0 || !IsOurPos(t)) continue;
         SetupForSymbol(m_pos.Symbol());
         m_trade.PositionClose(t);
         Print("[Trade] Emergency close #", t);
      }
      for(int i = OrdersTotal() - 1; i >= 0; i--) {
         ulong t = OrderGetTicket(i);
         if(t == 0 || !OrderSelect(t)) continue;
         if((ulong)OrderGetInteger(ORDER_MAGIC) != m_magic) continue;
         SetupForSymbol(OrderGetString(ORDER_SYMBOL));
         m_trade.OrderDelete(t);
      }
   }

   //-----------------------------------------------------------
   // COUNT HELPERS
   //-----------------------------------------------------------
   int CountPositions(string sym = "") {
      int c = 0;
      for(int i = PositionsTotal() - 1; i >= 0; i--) {
         ulong t = PositionGetTicket(i);
         if(t == 0 || !IsOurPos(t)) continue;
         if(sym == "" || m_pos.Symbol() == sym) c++;
      }
      return c;
   }

   int CountPending(string sym = "") {
      int c = 0;
      for(int i = OrdersTotal() - 1; i >= 0; i--) {
         ulong t = OrderGetTicket(i);
         if(t == 0 || !OrderSelect(t)) continue;
         if((ulong)OrderGetInteger(ORDER_MAGIC) != m_magic) continue;
         if(sym == "" || OrderGetString(ORDER_SYMBOL) == sym) c++;
      }
      return c;
   }

   double GetTotalFloatingPnL() {
      double pnl = 0;
      for(int i = PositionsTotal() - 1; i >= 0; i--) {
         ulong t = PositionGetTicket(i);
         if(t == 0 || !IsOurPos(t)) continue;
         pnl += m_pos.Profit() + m_pos.Swap();
      }
      return pnl;
   }
};

#endif // TRADEMANAGER_V2_MQH
