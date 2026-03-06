//+------------------------------------------------------------------+
//|                                               RiskManager.mqh   |
//|              Risk Management for SMC Scalper EA v7.0            |
//|                                                                  |
//|  v7.0: Realized P&L tracking. No emergency stops. Daily loss    |
//|  blocks new trades only. Smart lot sizing for small accounts.   |
//+------------------------------------------------------------------+
#ifndef RISKMANAGER_MQH
#define RISKMANAGER_MQH

#include "Defines.mqh"

class CRiskManager {
private:
   SRiskParams    m_params;
   SStreakControl m_streak;
   double         m_dayStartBalance;
   double         m_realizedPnL;
   datetime       m_currentDay;
   int            m_tradesToday;
   int            m_tradesOpened;
   bool           m_dailyTargetHit;
   bool           m_dailyLossHit;
   bool           m_ignoreDailyTarget;

   datetime GetGMTDate() {
      MqlDateTime dt;
      TimeToStruct(TimeGMT(), dt);
      dt.hour = 0; dt.min = 0; dt.sec = 0;
      return StructToTime(dt);
   }

   datetime GetServerDate() {
      MqlDateTime dt;
      TimeToStruct(TimeCurrent(), dt);
      dt.hour = 0; dt.min = 0; dt.sec = 0;
      return StructToTime(dt);
   }

   void CheckNewDay() {
      datetime today = GetServerDate();
      if(today != m_currentDay) {
         m_currentDay      = today;
         m_dayStartBalance = AccountInfoDouble(ACCOUNT_BALANCE);
         m_realizedPnL     = 0;
         m_tradesToday     = 0;
         m_tradesOpened    = 0;
         m_dailyTargetHit  = false;
         m_dailyLossHit    = false;
         m_streak.consecutiveLosses = 0;
         m_streak.consecutiveWins   = 0;
         m_streak.sizeMult          = 1.0;
         Print("[Risk] New day. Balance: $", DoubleToString(m_dayStartBalance, 2));
      }
   }

public:
   CRiskManager(double riskPct = 2.0, double maxDailyLoss = 10.0,
                double maxDailyProfit = 10.0, double maxDrawdown = 20.0,
                int maxTradesDay = 8, bool ignoreDailyTarget = false) {
      m_ignoreDailyTarget = ignoreDailyTarget;
      m_params.riskPct           = riskPct;
      m_params.maxDailyLossPct   = maxDailyLoss;
      m_params.maxDailyProfitPct = maxDailyProfit;
      m_params.maxDrawdownPct    = maxDrawdown;
      m_params.maxTradesPerDay   = maxTradesDay;
      m_params.minRR             = TARGET_RR;
      m_params.marginFloor       = MARGIN_KILL;

      ZeroMemory(m_streak);
      m_streak.sizeMult = 1.0;

      m_dayStartBalance = AccountInfoDouble(ACCOUNT_BALANCE);
      m_realizedPnL     = 0;
      m_tradesToday     = 0;
      m_tradesOpened    = 0;
      m_dailyTargetHit  = false;
      m_dailyLossHit    = false;
      m_currentDay      = GetServerDate();
   }

   void Update() {
      CheckNewDay();

      double realPct = 0;
      if(m_dayStartBalance > 0)
         realPct = (m_realizedPnL / m_dayStartBalance) * 100.0;

      if(!m_dailyTargetHit && realPct >= m_params.maxDailyProfitPct) {
         m_dailyTargetHit = true;
         Print("[Risk] DAILY TARGET HIT +", DoubleToString(realPct, 1),
               "% ($", DoubleToString(m_realizedPnL, 2), ")");
      }
      if(!m_dailyLossHit && realPct <= -(m_params.maxDailyLossPct)) {
         m_dailyLossHit = true;
         Print("[Risk] DAILY LOSS LIMIT ", DoubleToString(realPct, 1),
               "% ($", DoubleToString(m_realizedPnL, 2), ")");
      }
   }

   bool CanTrade(string &reason) {
      Update();
      if(m_dailyLossHit) { reason = "Daily loss limit hit"; return false; }
      if(m_dailyTargetHit && !m_ignoreDailyTarget) {
         reason = "Daily profit target hit";
         return false;
      }
      if(!m_ignoreDailyTarget && m_tradesOpened >= m_params.maxTradesPerDay) {
         reason = "Max trades/day reached";
         return false;
      }

      double ml = AccountInfoDouble(ACCOUNT_MARGIN_LEVEL);
      if(ml > 0 && ml < m_params.marginFloor) {
         reason = "Margin level critical";
         return false;
      }

      reason = "OK";
      return true;
   }

   void OnTradeOpened() {
      m_tradesOpened++;
      Print("[Risk] Trade #", IntegerToString(m_tradesOpened),
            "/", IntegerToString(m_params.maxTradesPerDay),
            " size x", DoubleToString(m_streak.sizeMult, 2));
   }

   double CalculateLot(string symbol, double entry, double sl) {
      double balance    = AccountInfoDouble(ACCOUNT_BALANCE);
      double riskAmount = balance * (m_params.riskPct / 100.0) * m_streak.sizeMult;
      double slDist     = MathAbs(entry - sl);
      if(slDist <= 0) return 0;

      double tickVal  = SymbolInfoDouble(symbol, SYMBOL_TRADE_TICK_VALUE);
      double tickSize = SymbolInfoDouble(symbol, SYMBOL_TRADE_TICK_SIZE);
      if(tickSize <= 0 || tickVal <= 0) {
         Print("[Risk] Invalid tick data for ", symbol);
         return 0;
      }

      double lossPerLot = (slDist / tickSize) * tickVal;
      if(lossPerLot <= 0) return 0;

      double lot     = riskAmount / lossPerLot;
      double minLot  = SymbolInfoDouble(symbol, SYMBOL_VOLUME_MIN);
      double maxLot  = SymbolInfoDouble(symbol, SYMBOL_VOLUME_MAX);
      double lotStep = SymbolInfoDouble(symbol, SYMBOL_VOLUME_STEP);

      if(lotStep <= 0) lotStep = 0.01;
      lot = MathFloor(lot / lotStep) * lotStep;
      lot = MathMin(maxLot, lot);

      if(lot < minLot) {
         double minLotLoss = minLot * lossPerLot;
         double minLotRiskPct = (minLotLoss / balance) * 100.0;
         // v8.0: Tighter check for small accounts. Max 1.5x riskPct (e.g. 3% if risk=2%)
         // Previously 3.0x (6%) was too loose for $20 accounts
         if(minLotRiskPct > m_params.riskPct * 1.5) {
            Print("[Risk] SKIP ", symbol, ": min lot ", DoubleToString(minLot, 2),
                  " risks ", DoubleToString(minLotRiskPct, 1),
                  "% (max ", DoubleToString(m_params.riskPct * 1.5, 1),
                  "%) bal=$", DoubleToString(balance, 2));
            return 0;
         }
         lot = minLot;
      }

      return lot;
   }

   void OnTradeClose(double pnl) {
      m_tradesToday++;
      m_realizedPnL += pnl;

      double realPct = 0;
      if(m_dayStartBalance > 0)
         realPct = (m_realizedPnL / m_dayStartBalance) * 100.0;
      Print("[Risk] Realized day P&L: $", DoubleToString(m_realizedPnL, 2),
            " (", DoubleToString(realPct, 1), "%)");

      if(pnl < 0) {
         m_streak.consecutiveLosses++;
         m_streak.consecutiveWins = 0;
         if(m_streak.consecutiveLosses >= LOSSES_HALF) {
            m_streak.sizeMult = 0.5;
            Print("[Risk] ", IntegerToString(m_streak.consecutiveLosses),
                  " consecutive losses - size at 50%");
         } else if(m_streak.consecutiveLosses >= LOSSES_REDUCE) {
            m_streak.sizeMult = 0.75;
            Print("[Risk] ", IntegerToString(m_streak.consecutiveLosses),
                  " consecutive losses - size at 75%");
         }
      } else if(pnl > 0) {
         m_streak.consecutiveWins++;
         if(m_streak.consecutiveLosses > 0)
            Print("[Risk] Win after ", IntegerToString(m_streak.consecutiveLosses),
                  " losses - restoring full size");
         m_streak.consecutiveLosses = 0;
         m_streak.sizeMult = 1.0;
      }
   }

   double GetDayPnL()       { return m_realizedPnL; }
   double GetDayPnLPct()    {
      if(m_dayStartBalance > 0)
         return (m_realizedPnL / m_dayStartBalance) * 100.0;
      return 0;
   }
   double GetStartBal()     { return m_dayStartBalance; }
   int    GetTradesToday()  { return m_tradesOpened; }
   bool   IsDailyDone()     { return (m_dailyTargetHit || m_dailyLossHit); }
   bool   IsTargetHit()     { return m_dailyTargetHit; }
   bool   IsLossHit()       { return m_dailyLossHit; }
   double GetSizeMult()     { return m_streak.sizeMult; }
   int    GetLosses()       { return m_streak.consecutiveLosses; }
   int    GetWins()         { return m_streak.consecutiveWins; }
   double GetRiskPct()      { return m_params.riskPct; }
   double GetTargetPct()    { return m_params.maxDailyProfitPct; }
   double GetLossLimitPct() { return m_params.maxDailyLossPct; }
};
#endif
