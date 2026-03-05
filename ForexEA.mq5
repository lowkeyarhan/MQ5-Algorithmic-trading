//+------------------------------------------------------------------+
//|                                                   ForexEA.mq5   |
//|              SMC Structure + Liquidity Sweep Scalper v4.0       |
//+------------------------------------------------------------------+
#property copyright "SMC_ScalperEA"
#property version   "4.0"
#property description "SMC Liquidity Sweep Scalper | OB/FVG Entry | 1:3 RR Minimum"
#property strict

#include "Include/Defines.mqh"
#include "Include/SilverBullet.mqh"
#include "Include/RiskManager.mqh"
#include "Include/TradeManager.mqh"
#include "Include/Logger.mqh"

//============================================================
//  INPUT PARAMETERS
//============================================================

input string   InpSep1        = "--- Pairs ---";
input bool     InpTradeEURUSD = true;
input bool     InpTradeGBPUSD = true;
input bool     InpTradeUSDJPY = true;
input bool     InpTradeXAUUSD = true;
input bool     InpTradeBTCUSD = false;

input string   InpSep2        = "--- Timeframes ---";
input ENUM_TIMEFRAMES InpTF   = PERIOD_M5;
input ENUM_TIMEFRAMES InpHTF  = PERIOD_M15;

input string   InpSep3        = "--- Risk ---";
input double   InpRiskPct     = 2.0;
input double   InpMaxDailyLoss = 6.0;
input double   InpMaxDailyProfit = 10.0;
input double   InpMaxDrawdown = 20.0;
input int      InpMaxTradesDay = 4;

input string   InpSep4        = "--- Trade Mgmt ---";
input bool     InpUseBreakeven = true;
input bool     InpUsePartial  = true;
input bool     InpUseTrail    = true;
input int      InpLimitTimeout = 25;
input int      InpSlippage    = 15;

input string   InpSep5        = "--- Display ---";
input bool     InpShowDashboard = true;

//============================================================
//  GLOBAL OBJECTS
//============================================================

struct SPairState {
   string        symbol;
   bool          active;
   CSilverBullet *engine;
   datetime      lastTradeTime;
   int           tradesThisSession;
   ENUM_SESSION  lastSession;
};

SPairState           g_pairs[];
int                  g_pairCount;
CRiskManager        *g_risk;
CTradeManager       *g_trade;
CLogger             *g_logger;
datetime             g_lastBar;
int                  g_totalTrades;
ENUM_SIGNAL_DIRECTION g_lastDir;
string               g_lastReason;

//============================================================
//  INITIALIZATION
//============================================================

int OnInit() {
   Print("=================================================");
   Print(EA_NAME, " v", EA_VERSION, " STARTING");
   Print("Strategy: SMC Liquidity Sweep + CHoCH + OB/FVG | 1:3 RR min");
   Print("Sessions: London 07:00-10:00 | NY 12:00-15:00 GMT");
   Print("=================================================");

   if(!TerminalInfoInteger(TERMINAL_TRADE_ALLOWED)) {
      Alert("Auto trading is disabled! Enable it in MT5.");
      return INIT_FAILED;
   }

   if(!MQLInfoInteger(MQL_TRADE_ALLOWED)) {
      Alert("Algo trading not allowed for this EA. Check settings.");
      return INIT_FAILED;
   }

   string allSyms[]  = { PAIR_EURUSD, PAIR_GBPUSD, PAIR_USDJPY, PAIR_XAUUSD, PAIR_BTCUSD };
   bool   allEnab[]  = { InpTradeEURUSD, InpTradeGBPUSD, InpTradeUSDJPY, InpTradeXAUUSD, InpTradeBTCUSD };

   g_pairCount = 0;
   ArrayResize(g_pairs, 5);

   for(int i = 0; i < 5; i++) {
      if(!allEnab[i]) continue;

      string sym = allSyms[i];
      bool found = (SymbolInfoDouble(sym, SYMBOL_BID) > 0);

      if(!found) {
         string suffixes[] = { ".r", "m", ".a", ".b", ".i", ".e", ".z", ".", "_" };
         for(int s = 0; s < ArraySize(suffixes); s++) {
            string trySymbol = allSyms[i] + suffixes[s];
            if(SymbolInfoDouble(trySymbol, SYMBOL_BID) > 0) {
               sym = trySymbol;
               found = true;
               Print("Found ", allSyms[i], " as ", sym);
               break;
            }
         }
      }

      if(!found) {
         Print("WARNING: ", allSyms[i], " not available - skipping");
         continue;
      }

      SymbolSelect(sym, true);

      g_pairs[g_pairCount].symbol            = sym;
      g_pairs[g_pairCount].active            = true;
      g_pairs[g_pairCount].engine            = new CSilverBullet(sym, InpTF, InpHTF);
      g_pairs[g_pairCount].lastTradeTime     = 0;
      g_pairs[g_pairCount].tradesThisSession = 0;
      g_pairs[g_pairCount].lastSession       = SESSION_NONE;
      g_pairCount++;
      Print("Pair registered: ", sym, " bid=", DoubleToString(SymbolInfoDouble(sym, SYMBOL_BID), 5));
   }

   if(g_pairCount == 0) {
      Alert("No valid pairs! Enable at least one pair.");
      return INIT_FAILED;
   }

   g_risk   = new CRiskManager(InpRiskPct, InpMaxDailyLoss, InpMaxDailyProfit,
                                InpMaxDrawdown, InpMaxTradesDay);
   g_trade  = new CTradeManager(InpSlippage, InpUseBreakeven, InpUsePartial, InpUseTrail);
   g_logger = new CLogger();
   if(InpShowDashboard) g_logger.Init();

   g_lastBar     = 0;
   g_totalTrades = 0;
   g_lastDir     = SIGNAL_NONE;
   g_lastReason  = "Waiting for killzone...";

   Print("Initialized: ", IntegerToString(g_pairCount), " pairs | Risk=",
         DoubleToString(InpRiskPct, 1), "% | Target=",
         DoubleToString(InpMaxDailyProfit, 1), "% | MaxLoss=",
         DoubleToString(InpMaxDailyLoss, 1), "%");

   datetime gmt = TimeGMT();
   datetime srv = TimeCurrent();
   int offset   = (int)(srv - gmt);
   Print("Broker time offset: UTC", (offset >= 0 ? "+" : ""),
         IntegerToString(offset/3600), " hours");

   EventSetTimer(30);
   return INIT_SUCCEEDED;
}

//============================================================
//  DEINITIALIZATION
//============================================================

void OnDeinit(const int reason) {
   if(g_logger) { g_logger.Cleanup(); delete g_logger; g_logger = NULL; }
   if(g_risk)   { delete g_risk;  g_risk  = NULL; }
   if(g_trade)  { delete g_trade; g_trade = NULL; }

   for(int i = 0; i < g_pairCount; i++) {
      if(g_pairs[i].engine) { delete g_pairs[i].engine; g_pairs[i].engine = NULL; }
   }
   EventKillTimer();
   Print(EA_NAME, " deinitialized. Reason: ", IntegerToString(reason));
}

//============================================================
//  MAIN TICK
//============================================================

void OnTick() {
   bool isNewBar = false;
   for(int i = 0; i < g_pairCount; i++) {
      datetime barT = iTime(g_pairs[i].symbol, InpTF, 0);
      if(barT > 0 && barT != g_lastBar) {
         isNewBar  = true;
         g_lastBar = barT;
         break;
      }
   }

   if(g_trade) g_trade.ManagePositions();

   if(!isNewBar) return;

   g_trade.CancelStaleLimits(InpLimitTimeout);
   g_risk.Update();

   string riskReason;
   bool canTrade = g_risk.CanTrade(riskReason);

   for(int i = 0; i < g_pairCount; i++) {
      if(!g_pairs[i].active) continue;
      ProcessPair(i, canTrade, riskReason);
   }

   if(InpShowDashboard) UpdateDashboard();
}

//============================================================
//  PROCESS SINGLE PAIR
//============================================================

void ProcessPair(int idx, bool canTrade, string riskReason) {
   CSilverBullet *engine = g_pairs[idx].engine;
   string symbol = g_pairs[idx].symbol;

   ENUM_SESSION currentSes = engine.GetSession();
   if(currentSes != g_pairs[idx].lastSession) {
      if(currentSes == SESSION_LONDON_KILL || currentSes == SESSION_NY_KILL) {
         g_pairs[idx].tradesThisSession = 0;
         engine.ResetSession();
         Print("[", symbol, "] New session: ", engine.GetSessionName());
      }
      g_pairs[idx].lastSession = currentSes;
   }

   bool setupReady = engine.Update();

   if(symbol == _Symbol && InpShowDashboard) {
      SAsiaLevels asia = engine.GetAsiaLevels();
      if(asia.valid) g_logger.DrawAsiaLevels(symbol, asia.high, asia.low);
   }

   if(g_trade.CountPositions(symbol) > 0) return;
   if(g_trade.CountPending(symbol) > 0) return;

   if(!setupReady) return;

   if(!canTrade) {
      Print("[", symbol, "] Setup ready but blocked: ", riskReason);
      return;
   }

   if(g_pairs[idx].tradesThisSession >= 2) {
      Print("[", symbol, "] Already traded 2x this session");
      return;
   }

   SSetup setup = engine.GetSetup();

   int setupAge = (int)((TimeCurrent() - setup.setupTime) / PeriodSeconds(InpTF));
   if(setupAge > 10) {
      Print("[", symbol, "] Setup too old (", IntegerToString(setupAge), " bars)");
      return;
   }

   double lot = g_risk.CalculateLot(symbol, setup.entryPrice, setup.stopLoss);
   if(lot <= 0) {
      Print("[", symbol, "] Lot calculation failed");
      return;
   }

   bool placed = false;
   if(setup.direction == SIGNAL_BUY)
      placed = g_trade.PlaceBuyLimit(symbol, setup.entryPrice, setup.stopLoss, setup.takeProfit, lot);
   else if(setup.direction == SIGNAL_SELL)
      placed = g_trade.PlaceSellLimit(symbol, setup.entryPrice, setup.stopLoss, setup.takeProfit, lot);

   if(placed) {
      engine.OnTradePlaced();
      g_pairs[idx].tradesThisSession++;
      g_pairs[idx].lastTradeTime = TimeCurrent();
      g_totalTrades++;
      g_lastDir    = setup.direction;
      g_lastReason = setup.reason;
      g_risk.OnTradeOpened();

      if(symbol == _Symbol && InpShowDashboard) {
         g_logger.DrawFVG(symbol, setup.fvg.upper, setup.fvg.lower,
                          setup.fvg.isBullish, setup.fvg.time);
         SAsiaLevels asia = engine.GetAsiaLevels();
         g_logger.DrawSweepArrow(symbol, setup.direction == SIGNAL_BUY,
                                 asia.sweepWickTip, asia.sweepTime);
      }

      string dirStr = (setup.direction == SIGNAL_BUY) ? "BUY" : "SELL";
      string sesStr = (setup.session == SESSION_LONDON_KILL) ? "London" : "NY";
      Print("====================================");
      Print("  ORDER: ", symbol, " ", dirStr);
      Print("  Entry: ", DoubleToString(setup.entryPrice, 5));
      Print("  SL   : ", DoubleToString(setup.stopLoss, 5),
            " (", DoubleToString(setup.slPips, 1), " pips)");
      Print("  TP   : ", DoubleToString(setup.takeProfit, 5),
            " (RR 1:", DoubleToString(setup.riskReward, 1), ")");
      Print("  Lot  : ", DoubleToString(lot, 2));
      Print("  Ses  : ", sesStr, " Killzone");
      Print("====================================");
   }
}

//============================================================
//  TRADE EVENT
//============================================================

void OnTradeTransaction(const MqlTradeTransaction &trans,
                        const MqlTradeRequest &request,
                        const MqlTradeResult &result) {
   if(trans.type != TRADE_TRANSACTION_DEAL_ADD) return;

   if(HistoryDealSelect(trans.deal)) {
      ulong  magic  = HistoryDealGetInteger(trans.deal, DEAL_MAGIC);
      double profit = HistoryDealGetDouble(trans.deal, DEAL_PROFIT);
      double swap   = HistoryDealGetDouble(trans.deal, DEAL_SWAP);
      double comm   = HistoryDealGetDouble(trans.deal, DEAL_COMMISSION);
      long   entry  = HistoryDealGetInteger(trans.deal, DEAL_ENTRY);
      string symbol = HistoryDealGetString(trans.deal, DEAL_SYMBOL);

      if(magic != MAGIC_NUMBER) return;
      if(entry != DEAL_ENTRY_OUT && entry != DEAL_ENTRY_INOUT) return;

      double netPnL = profit + swap + comm;
      g_risk.OnTradeClose(netPnL);

      for(int i = 0; i < g_pairCount; i++) {
         if(g_pairs[i].symbol == symbol)
            g_pairs[i].engine.OnTradeClose();
      }

      string outcome = "BE";
      if(netPnL > 0) outcome = "WIN";
      if(netPnL < 0) outcome = "LOSS";
      Print("=== CLOSED: ", symbol, " ", outcome,
            " $", DoubleToString(netPnL, 2),
            " | Day: ", DoubleToString(g_risk.GetDayPnLPct(), 2), "%");
   }
}

//============================================================
//  TIMER
//============================================================

void OnTimer() {
   MqlDateTime dt;
   TimeToStruct(TimeGMT(), dt);

   if(dt.hour == 0 && dt.min == 0) {
      for(int i = 0; i < g_pairCount; i++) {
         g_pairs[i].tradesThisSession = 0;
         g_pairs[i].lastSession       = SESSION_NONE;
         g_pairs[i].engine.ResetDay();
      }
      Print("=== DAILY RESET ===");
   }
}

//============================================================
//  DASHBOARD UPDATE
//============================================================

void UpdateDashboard() {
   if(!InpShowDashboard || !g_risk || !g_logger) return;

   SAsiaLevels asia;
   ZeroMemory(asia);
   string phase   = "Idle";
   string session = "Off-Session";

   for(int i = 0; i < g_pairCount; i++) {
      if(g_pairs[i].symbol == _Symbol) {
         asia    = g_pairs[i].engine.GetAsiaLevels();
         phase   = EnumToString(g_pairs[i].engine.GetSetup().phase);
         session = g_pairs[i].engine.GetSessionName();
         break;
      }
   }

   g_logger.UpdateDashboard(
      _Symbol,
      session,
      phase,
      asia.valid ? asia.high : 0,
      asia.valid ? asia.low  : 0,
      AccountInfoDouble(ACCOUNT_BALANCE),
      g_risk.GetDayPnL(),
      g_risk.GetDayPnLPct(),
      g_risk.GetTradesToday(),
      g_risk.GetLosses(),
      g_risk.GetWins(),
      g_risk.GetSizeMult(),
      g_risk.IsTargetHit(),
      g_risk.IsLossHit(),
      g_lastReason,
      g_lastDir
   );
}
