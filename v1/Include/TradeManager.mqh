//+------------------------------------------------------------------+
//|                                               TradeManager.mqh  |
//|              Trade Execution for SMC Scalper EA v7.0            |
//|                                                                  |
//|  v7.0: BE at 1.5R, Partial 25% at 2.5R, Trail 1.5R distance.  |
//|  Let winners develop. Wider trail prevents premature stops.      |
//+------------------------------------------------------------------+
#ifndef TRADEMANAGER_MQH
#define TRADEMANAGER_MQH

#include "Defines.mqh"
#include <Trade\Trade.mqh>
#include <Trade\PositionInfo.mqh>
#include <Trade\OrderInfo.mqh>

class CTradeManager {
private:
   CTrade m_trade;
   CPositionInfo m_pos;
   COrderInfo m_ord;

   int m_slippage;
   bool m_useBreakeven;
   bool m_usePartial;
   bool m_useTrail;

   struct SPendingOrder {
      string symbol;
      ulong ticket;
      datetime placedTime;
      double entry;
      double sl;
      double tp;
      bool active;
   };
   SPendingOrder m_pending[];
   int m_pendingCount;

   ulong m_partialDone[];
   int m_partialCount;

   bool IsPartialDone(ulong ticket) {
      for(int i = 0; i < m_partialCount; i++) {
         if(m_partialDone[i] == ticket) return true;
      }
      return false;
   }

   void MarkPartialDone(ulong ticket) {
      if(m_partialCount < ArraySize(m_partialDone)) {
         m_partialDone[m_partialCount] = ticket;
         m_partialCount++;
      }
   }

   int FindPending(string symbol) {
      for(int i = 0; i < m_pendingCount; i++) {
         if(m_pending[i].symbol == symbol && m_pending[i].active)
            return i;
      }
      return -1;
   }

   bool IsOurOrder(ulong ticket) {
      if(!OrderSelect(ticket)) return false;
      return (OrderGetInteger(ORDER_MAGIC) == MAGIC_NUMBER);
   }

   bool IsOurPosition(ulong ticket) {
      if(!m_pos.SelectByTicket(ticket)) return false;
      return (m_pos.Magic() == MAGIC_NUMBER);
   }

   ENUM_ORDER_TYPE_FILLING GetFilling(string symbol) {
      long fillMode = SymbolInfoInteger(symbol, SYMBOL_FILLING_MODE);
      if((fillMode & SYMBOL_FILLING_FOK) != 0) return ORDER_FILLING_FOK;
      if((fillMode & SYMBOL_FILLING_IOC) != 0) return ORDER_FILLING_IOC;
      return ORDER_FILLING_RETURN;
   }

   void SetupTradeForSymbol(string symbol) {
      m_trade.SetExpertMagicNumber(MAGIC_NUMBER);
      m_trade.SetDeviationInPoints(m_slippage);
      m_trade.SetTypeFilling(GetFilling(symbol));
   }

   void AddPending(string symbol, ulong ticket, double entry, double sl, double tp) {
      if(m_pendingCount >= ArraySize(m_pending))
         ArrayResize(m_pending, m_pendingCount + 10);
      m_pending[m_pendingCount].symbol = symbol;
      m_pending[m_pendingCount].ticket = ticket;
      m_pending[m_pendingCount].placedTime = TimeCurrent();
      m_pending[m_pendingCount].entry = entry;
      m_pending[m_pendingCount].sl = sl;
      m_pending[m_pendingCount].tp = tp;
      m_pending[m_pendingCount].active = true;
      m_pendingCount++;
   }

public:
   CTradeManager(int slippage = 10, bool useBreakeven = true,
                 bool usePartial = true, bool useTrail = true) {
      m_slippage = slippage;
      m_useBreakeven = useBreakeven;
      m_usePartial = usePartial;
      m_useTrail = useTrail;

      m_trade.SetExpertMagicNumber(MAGIC_NUMBER);
      m_trade.SetDeviationInPoints(slippage);

      m_pendingCount = 0;
      ArrayResize(m_pending, 30);
      m_partialCount = 0;
      ArrayResize(m_partialDone, 30);
   }

   bool PlaceBuyLimit(string symbol, double entry, double sl, double tp, double lot) {
      SetupTradeForSymbol(symbol);
      int digits = (int)SymbolInfoInteger(symbol, SYMBOL_DIGITS);
      entry = NormalizeDouble(entry, digits);
      sl = NormalizeDouble(sl, digits);
      tp = NormalizeDouble(tp, digits);

      double ask = SymbolInfoDouble(symbol, SYMBOL_ASK);
      double point = SymbolInfoDouble(symbol, SYMBOL_POINT);

      double tolerance = point * 20;
      if(ask <= entry + tolerance) {
         Print("[Trade] BUY MARKET(price at entry): ", symbol,
               " ask=", DoubleToString(ask, digits),
               " entry=", DoubleToString(entry, digits));
         bool ok = m_trade.Buy(lot, symbol, 0, sl, tp, "SMC_BUY_MKT");
         if(!ok) {
            Print("[Trade] BUY MARKET FAILED: ", symbol,
                  " err=", IntegerToString(GetLastError()),
                  " ret=", IntegerToString(m_trade.ResultRetcode()));
            return false;
         }
         return true;
      }

      bool ok = m_trade.BuyLimit(lot, entry, symbol, sl, tp, ORDER_TIME_GTC, 0, "SMC_BUY_LIM");
      if(!ok) {
         uint retcode = m_trade.ResultRetcode();
         Print("[Trade] BuyLimit FAILED: ", symbol,
               " err=", IntegerToString(GetLastError()),
               " ret=", IntegerToString(retcode));
         if(retcode == 10016 || retcode == 10015 || retcode == 10014) {
            bool fb = m_trade.Buy(lot, symbol, 0, sl, tp, "SMC_BUY_FB");
            if(fb) return true;
         }
         return false;
      }

      AddPending(symbol, m_trade.ResultOrder(), entry, sl, tp);
      Print("[Trade] BUY LIMIT: ", symbol,
            " @", DoubleToString(entry, digits),
            " SL=", DoubleToString(sl, digits),
            " TP=", DoubleToString(tp, digits),
            " Lot=", DoubleToString(lot, 2));
      return true;
   }

   bool PlaceSellLimit(string symbol, double entry, double sl, double tp, double lot) {
      SetupTradeForSymbol(symbol);
      int digits = (int)SymbolInfoInteger(symbol, SYMBOL_DIGITS);
      entry = NormalizeDouble(entry, digits);
      sl = NormalizeDouble(sl, digits);
      tp = NormalizeDouble(tp, digits);

      double bid = SymbolInfoDouble(symbol, SYMBOL_BID);
      double point = SymbolInfoDouble(symbol, SYMBOL_POINT);

      double tolerance = point * 20;
      if(bid >= entry - tolerance) {
         Print("[Trade] SELL MARKET(price at entry): ", symbol,
               " bid=", DoubleToString(bid, digits),
               " entry=", DoubleToString(entry, digits));
         bool ok = m_trade.Sell(lot, symbol, 0, sl, tp, "SMC_SELL_MKT");
         if(!ok) {
            Print("[Trade] SELL MARKET FAILED: ", symbol,
                  " err=", IntegerToString(GetLastError()),
                  " ret=", IntegerToString(m_trade.ResultRetcode()));
            return false;
         }
         return true;
      }

      bool ok = m_trade.SellLimit(lot, entry, symbol, sl, tp, ORDER_TIME_GTC, 0, "SMC_SELL_LIM");
      if(!ok) {
         uint retcode = m_trade.ResultRetcode();
         Print("[Trade] SellLimit FAILED: ", symbol,
               " err=", IntegerToString(GetLastError()),
               " ret=", IntegerToString(retcode));
         if(retcode == 10016 || retcode == 10015 || retcode == 10014) {
            bool fb = m_trade.Sell(lot, symbol, 0, sl, tp, "SMC_SELL_FB");
            if(fb) return true;
         }
         return false;
      }

      AddPending(symbol, m_trade.ResultOrder(), entry, sl, tp);
      Print("[Trade] SELL LIMIT: ", symbol,
            " @", DoubleToString(entry, digits),
            " SL=", DoubleToString(sl, digits),
            " TP=", DoubleToString(tp, digits),
            " Lot=", DoubleToString(lot, 2));
      return true;
   }

   void CancelStaleLimits(int timeoutMinutes = 30) {
      for(int i = 0; i < m_pendingCount; i++) {
         if(!m_pending[i].active) continue;
         int age = (int)((TimeCurrent() - m_pending[i].placedTime) / 60);
         if(age < timeoutMinutes) continue;

         ulong ticket = m_pending[i].ticket;
         if(IsOurOrder(ticket)) {
            SetupTradeForSymbol(m_pending[i].symbol);
            m_trade.OrderDelete(ticket);
            Print("[Trade] Cancelled stale limit #", IntegerToString((long)ticket),
                  " ", m_pending[i].symbol, " age=", IntegerToString(age), "min");
         }
         m_pending[i].active = false;
      }

      for(int i = OrdersTotal() - 1; i >= 0; i--) {
         ulong ticket = OrderGetTicket(i);
         if(ticket == 0) continue;
         if(!OrderSelect(ticket)) continue;
         if(OrderGetInteger(ORDER_MAGIC) != MAGIC_NUMBER) continue;
         datetime placed = (datetime)OrderGetInteger(ORDER_TIME_SETUP);
         int age = (int)((TimeCurrent() - placed) / 60);
         if(age >= timeoutMinutes) {
            string sym = OrderGetString(ORDER_SYMBOL);
            SetupTradeForSymbol(sym);
            m_trade.OrderDelete(ticket);
            Print("[Trade] Cleaned stale order #", IntegerToString((long)ticket),
                  " ", sym, " age=", IntegerToString(age), "min");
         }
      }
   }

   void ManagePositions() {
      int total = PositionsTotal();
      for(int i = total - 1; i >= 0; i--) {
         ulong ticket = PositionGetTicket(i);
         if(ticket == 0) continue;
         if(!IsOurPosition(ticket)) continue;

         string symbol = m_pos.Symbol();
         double openP = m_pos.PriceOpen();
         double sl = m_pos.StopLoss();
         double tp = m_pos.TakeProfit();
         double lots = m_pos.Volume();
         double bid = SymbolInfoDouble(symbol, SYMBOL_BID);
         double ask = SymbolInfoDouble(symbol, SYMBOL_ASK);
         int digits = (int)SymbolInfoInteger(symbol, SYMBOL_DIGITS);
         double point = SymbolInfoDouble(symbol, SYMBOL_POINT);

         double slDist = MathAbs(openP - sl);
         if(slDist <= 0) continue;

         bool isBuy = (m_pos.PositionType() == POSITION_TYPE_BUY);
         double currentPrice = isBuy ? bid : ask;
         double profit = isBuy ? (currentPrice - openP) : (openP - currentPrice);
         double rMultiple = profit / slDist;

         SetupTradeForSymbol(symbol);

         // BREAKEVEN at BE_R_LEVEL (1.5R)
         if(m_useBreakeven && rMultiple >= BE_R_LEVEL) {
            double beBuf = point * 5;
            double newSL;
            if(isBuy)
               newSL = NormalizeDouble(openP + beBuf, digits);
            else
               newSL = NormalizeDouble(openP - beBuf, digits);

            bool alreadyBE = isBuy ? (sl >= openP) : (sl <= openP);
            if(!alreadyBE) {
               bool modified = m_trade.PositionModify(ticket, newSL, tp);
               if(modified)
                  Print("[Trade] BE @", DoubleToString(rMultiple, 1), "R: ",
                        symbol, " SL->", DoubleToString(newSL, digits));
            }
         }

         // PARTIAL CLOSE at PARTIAL_R_LEVEL (2.5R)
         if(m_usePartial && rMultiple >= PARTIAL_R_LEVEL && !IsPartialDone(ticket)) {
            double minLot = SymbolInfoDouble(symbol, SYMBOL_VOLUME_MIN);
            double lotStep = SymbolInfoDouble(symbol, SYMBOL_VOLUME_STEP);
            if(lots > minLot * 1.5) {
               double closeLots = MathFloor((lots * PARTIAL_PCT) / lotStep) * lotStep;
               closeLots = MathMax(closeLots, minLot);
               if(closeLots >= minLot && closeLots < lots) {
                  bool closed = m_trade.PositionClosePartial(ticket, closeLots);
                  if(closed) {
                     MarkPartialDone(ticket);
                     Print("[Trade] PARTIAL ", IntegerToString((int)(PARTIAL_PCT * 100)),
                           "% @", DoubleToString(rMultiple, 1), "R: ", symbol,
                           " closed ", DoubleToString(closeLots, 2), " lots");
                  }
               }
            }
         }

         // TRAIL at TRAIL_R_DISTANCE behind price, starting at TRAIL_R_START
         if(m_useTrail && rMultiple >= TRAIL_R_START) {
            double trailDist = slDist * TRAIL_R_DISTANCE;
            if(isBuy) {
               double newSL = NormalizeDouble(currentPrice - trailDist, digits);
               if(newSL > sl + point) {
                  bool trailed = m_trade.PositionModify(ticket, newSL, tp);
                  if(trailed)
                     Print("[Trade] Trail @", DoubleToString(rMultiple, 1),
                           "R: ", symbol, " SL->", DoubleToString(newSL, digits));
               }
            } else {
               double newSL = NormalizeDouble(currentPrice + trailDist, digits);
               if(newSL < sl - point) {
                  bool trailed = m_trade.PositionModify(ticket, newSL, tp);
                  if(trailed)
                     Print("[Trade] Trail @", DoubleToString(rMultiple, 1),
                           "R: ", symbol, " SL->", DoubleToString(newSL, digits));
               }
            }
         }
      }
   }

   int CountPositions(string symbol = "") {
      int count = 0;
      for(int i = 0; i < PositionsTotal(); i++) {
         ulong ticket = PositionGetTicket(i);
         if(ticket == 0) continue;
         if(!IsOurPosition(ticket)) continue;
         if(symbol == "" || m_pos.Symbol() == symbol) count++;
      }
      return count;
   }

   int CountPending(string symbol = "") {
      int count = 0;
      for(int i = OrdersTotal() - 1; i >= 0; i--) {
         ulong ticket = OrderGetTicket(i);
         if(ticket == 0) continue;
         if(!OrderSelect(ticket)) continue;
         if(OrderGetInteger(ORDER_MAGIC) != MAGIC_NUMBER) continue;
         string sym = OrderGetString(ORDER_SYMBOL);
         if(symbol == "" || sym == symbol) count++;
      }
      for(int i = 0; i < m_pendingCount; i++) {
         if(!m_pending[i].active) continue;
         if(!IsOurOrder(m_pending[i].ticket))
            m_pending[i].active = false;
      }
      return count;
   }

   void CloseAll() {
      int i;
      for(i = PositionsTotal() - 1; i >= 0; i--) {
         ulong ticket = PositionGetTicket(i);
         if(ticket == 0) continue;
         if(IsOurPosition(ticket)) {
            SetupTradeForSymbol(m_pos.Symbol());
            bool closed = m_trade.PositionClose(ticket);
            if(closed) Print("[Trade] Emergency closed #", IntegerToString((long)ticket));
         }
      }
      for(i = OrdersTotal() - 1; i >= 0; i--) {
         ulong ticket = OrderGetTicket(i);
         if(ticket == 0) continue;
         if(!OrderSelect(ticket)) continue;
         if(OrderGetInteger(ORDER_MAGIC) == MAGIC_NUMBER) {
            SetupTradeForSymbol(OrderGetString(ORDER_SYMBOL));
            bool deleted = m_trade.OrderDelete(ticket);
            if(deleted) Print("[Trade] Emergency deleted #", IntegerToString((long)ticket));
         }
      }
   }

   double GetTotalFloatingPnL() {
      double pnl = 0;
      for(int i = 0; i < PositionsTotal(); i++) {
         ulong ticket = PositionGetTicket(i);
         if(ticket == 0) continue;
         if(IsOurPosition(ticket)) {
            pnl = pnl + m_pos.Profit() + m_pos.Swap();
         }
      }
      return pnl;
   }
};
#endif
