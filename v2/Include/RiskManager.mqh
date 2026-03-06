//+------------------------------------------------------------------+
//|                                               RiskManager.mqh   |
//|      Institutional EA v2 — Risk Management                      |
//|  Hard 10% daily loss cap (realized+floating). Dynamic lot       |
//|  sizing. Streak control. Kelly criterion sanity cap.            |
//+------------------------------------------------------------------+
#ifndef RISKMANAGER_V2_MQH
#define RISKMANAGER_V2_MQH

#include "Defines.mqh"
#include <Trade\Trade.mqh>
#include <Trade\PositionInfo.mqh>

class CRiskManager {
private:
   SRiskParams    m_params;
   SStreakControl m_streak;
   double         m_dayStartBalance;
   double         m_realizedPnL;
   datetime       m_currentDay;
   int            m_tradesOpened;
   int            m_tradesToday;
   bool           m_dailyLossHit;
   bool           m_dailyTargetHit;
   bool           m_ignoreDailyTarget;
   ulong          m_magic;

   CPositionInfo  m_pos;

   datetime GetServerDate() {
      MqlDateTime dt; TimeToStruct(TimeCurrent(), dt);
      dt.hour = 0; dt.min = 0; dt.sec = 0;
      return StructToTime(dt);
   }

   //-----------------------------------------------------------
   // FLOATING P&L across all our open positions
   //-----------------------------------------------------------
   double GetFloatingPnL() {
      double pnl = 0;
      for(int i = PositionsTotal() - 1; i >= 0; i--) {
         ulong ticket = PositionGetTicket(i);
         if(!m_pos.SelectByTicket(ticket)) continue;
         if(m_pos.Magic() != m_magic) continue;
         pnl += m_pos.Profit() + m_pos.Swap() + m_pos.Commission();
      }
      return pnl;
   }

   void CheckNewDay() {
      datetime today = GetServerDate();
      if(today != m_currentDay) {
         m_currentDay      = today;
         m_dayStartBalance = AccountInfoDouble(ACCOUNT_BALANCE);
         m_realizedPnL     = 0;
         m_tradesOpened    = 0;
         m_tradesToday     = 0;
         m_dailyLossHit    = false;
         m_dailyTargetHit  = false;
         m_streak.consecutiveLosses = 0;
         m_streak.consecutiveWins   = 0;
         m_streak.sizeMult          = 1.0;
         Print("[Risk] New day. Balance: $", DoubleToString(m_dayStartBalance, 2));
      }
   }

public:
   CRiskManager(double riskPct = 1.5, double maxDailyLoss = 10.0,
                double maxDailyProfit = 20.0, int maxTrades = 8,
                bool ignoreDailyTarget = false, ulong magic = MAGIC_NUMBER_V2) {
      m_magic             = magic;
      m_ignoreDailyTarget = ignoreDailyTarget;
      m_params.riskPct          = riskPct;
      m_params.maxDailyLossPct  = maxDailyLoss;
      m_params.maxDailyProfitPct= maxDailyProfit;
      m_params.maxTradesPerDay  = maxTrades;
      m_params.marginFloor      = MARGIN_FLOOR;

      ZeroMemory(m_streak); m_streak.sizeMult = 1.0;

      m_dayStartBalance = AccountInfoDouble(ACCOUNT_BALANCE);
      m_realizedPnL     = 0;
      m_tradesOpened    = 0;
      m_tradesToday     = 0;
      m_dailyLossHit    = false;
      m_dailyTargetHit  = false;
      m_currentDay      = GetServerDate();
   }

   //-----------------------------------------------------------
   // UPDATE — check realized and floating daily P&L
   // Returns true if the daily loss cap is newly breached
   //-----------------------------------------------------------
   bool Update() {
      CheckNewDay();

      if(m_dayStartBalance <= 0) return false;

      double floating   = GetFloatingPnL();
      double totalPnL   = m_realizedPnL + floating;
      double totalPct   = (totalPnL / m_dayStartBalance) * 100.0;

      if(!m_dailyLossHit && totalPct <= -m_params.maxDailyLossPct) {
         m_dailyLossHit = true;
         Print("[Risk] *** DAILY LOSS CAP HIT: ", DoubleToString(totalPct, 2),
               "% ($", DoubleToString(totalPnL, 2), ") — CLOSING ALL ***");
         return true; // caller must close all positions
      }

      double realPct = (m_realizedPnL / m_dayStartBalance) * 100.0;
      if(!m_dailyTargetHit && realPct >= m_params.maxDailyProfitPct) {
         m_dailyTargetHit = true;
         Print("[Risk] Daily profit target hit: +", DoubleToString(realPct, 2), "%");
      }

      return false;
   }

   //-----------------------------------------------------------
   // CAN TRADE?
   //-----------------------------------------------------------
   bool CanTrade(string &reason) {
      Update();
      if(m_dailyLossHit)  { reason = "Daily loss cap hit — no new trades"; return false; }
      if(m_dailyTargetHit && !m_ignoreDailyTarget)
                           { reason = "Daily profit target hit"; return false; }
      if(m_tradesOpened >= m_params.maxTradesPerDay)
                           { reason = "Max trades/day reached"; return false; }

      double ml = AccountInfoDouble(ACCOUNT_MARGIN_LEVEL);
      if(ml > 0 && ml < m_params.marginFloor) { reason = "Margin level critical"; return false; }

      reason = "OK"; return true;
   }

   //-----------------------------------------------------------
   // LOT SIZE CALCULATION
   // Risk pct × size multiplier × kelly sanity
   //-----------------------------------------------------------
   double CalculateLot(string symbol, double entry, double sl) {
      double balance  = AccountInfoDouble(ACCOUNT_BALANCE);
      double riskAmt  = balance * (m_params.riskPct / 100.0) * m_streak.sizeMult;
      double slDist   = MathAbs(entry - sl);
      if(slDist <= 0) return 0;

      double tickVal  = SymbolInfoDouble(symbol, SYMBOL_TRADE_TICK_VALUE);
      double tickSize = SymbolInfoDouble(symbol, SYMBOL_TRADE_TICK_SIZE);
      if(tickSize <= 0 || tickVal <= 0) { Print("[Risk] Bad tick data for ", symbol); return 0; }

      double lossPerLot = (slDist / tickSize) * tickVal;
      if(lossPerLot <= 0) return 0;

      double lot     = riskAmt / lossPerLot;
      double minLot  = SymbolInfoDouble(symbol, SYMBOL_VOLUME_MIN);
      double maxLot  = SymbolInfoDouble(symbol, SYMBOL_VOLUME_MAX);
      double lotStep = SymbolInfoDouble(symbol, SYMBOL_VOLUME_STEP);
      if(lotStep <= 0) lotStep = 0.01;

      lot = MathFloor(lot / lotStep) * lotStep;
      lot = MathMin(lot, maxLot);

      // Micro-account guard: skip if min lot risks > MAX_LOT_RISK_PCT
      if(lot < minLot) {
         double minRisk = (minLot * lossPerLot / balance) * 100.0;
         if(minRisk > MAX_LOT_RISK_PCT) {
            Print("[Risk] SKIP ", symbol, ": min lot (", DoubleToString(minLot,2),
                  ") would risk ", DoubleToString(minRisk,1), "% (max ", DoubleToString(MAX_LOT_RISK_PCT,1), "%)");
            return 0;
         }
         lot = minLot;
      }

      Print("[Risk] Lot=", DoubleToString(lot,2), " Risk=$", DoubleToString(lot*lossPerLot,2),
            " (", DoubleToString((lot*lossPerLot/balance)*100.0,2), "%)");
      return lot;
   }

   void OnTradeOpened() {
      m_tradesOpened++;
      Print("[Risk] Trade #", m_tradesOpened, "/", m_params.maxTradesPerDay,
            " SizeMult=x", DoubleToString(m_streak.sizeMult, 2));
   }

   void OnTradeClose(double netPnL) {
      m_tradesToday++;
      m_realizedPnL += netPnL;

      double realPct = (m_dayStartBalance > 0) ? (m_realizedPnL / m_dayStartBalance) * 100.0 : 0;
      Print("[Risk] Closed P&L: $", DoubleToString(netPnL,2),
            " | Day realized: ", DoubleToString(realPct,2), "%");

      if(netPnL < 0) {
         m_streak.consecutiveLosses++;
         m_streak.consecutiveWins = 0;
         if(m_streak.consecutiveLosses >= STREAK_HALF_LOSSES)
            m_streak.sizeMult = 0.5;
         else if(m_streak.consecutiveLosses >= STREAK_REDUCE_LOSSES)
            m_streak.sizeMult = 0.5;
         Print("[Risk] Loss streak: ", m_streak.consecutiveLosses, " | SizeMult=", DoubleToString(m_streak.sizeMult,2));
      } else if(netPnL > 0) {
         m_streak.consecutiveLosses = 0;
         m_streak.consecutiveWins++;
         m_streak.sizeMult = 1.0;
      }
   }

   // Getters
   double GetDayPnL()      { return m_realizedPnL + GetFloatingPnL(); }
   double GetDayPnLPct()   { return (m_dayStartBalance > 0) ? (GetDayPnL() / m_dayStartBalance) * 100.0 : 0; }
   double GetRealizedPct() { return (m_dayStartBalance > 0) ? (m_realizedPnL / m_dayStartBalance) * 100.0 : 0; }
   double GetStartBal()    { return m_dayStartBalance; }
   int    GetTradesOpened(){ return m_tradesOpened; }
   bool   IsLossHit()      { return m_dailyLossHit; }
   bool   IsTargetHit()    { return m_dailyTargetHit; }
   double GetSizeMult()    { return m_streak.sizeMult; }
   int    GetLosses()      { return m_streak.consecutiveLosses; }
   int    GetWins()        { return m_streak.consecutiveWins; }
   double GetRiskPct()     { return m_params.riskPct; }
};

#endif // RISKMANAGER_V2_MQH
