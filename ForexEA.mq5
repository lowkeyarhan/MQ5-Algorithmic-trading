//+------------------------------------------------------------------+
//|                                                   ForexEA.mq5   |
//|              SMC Structure + Liquidity Sweep Scalper v6.0       |
//|                                                                  |
//|  v6.0: No pausing. 10% daily loss hard cap. Let strategy work. |
//+------------------------------------------------------------------+
#property copyright "SMC_ScalperEA"
#property version   "6.0"
#property description "SMC Scalper | Asia Sweep + Swing BOS | OB/FVG Entry | 1:3 RR Min"
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
input double   InpRiskPct     = 2.0;              // Risk % per trade
input double   InpMaxDailyLoss = 10.0;            // Max daily loss % (HARD CAP)
input double   InpMaxDailyProfit = 15.0;          // Daily profit target %
input int      InpMaxTradesDay = 8;               // Max trades per day

input bool     InpIgnoreDailyTarget = true;        // Ignore daily target (testing only)

input string   InpSep4        = "--- Trade Mgmt ---";
input bool     InpUseBreakeven = true;
input bool     InpUsePartial  = true;
input bool     InpUseTrail    = true;
input int      InpLimitTimeout = 20;               // Limit order timeout (min)
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
   Print("Strategy: SMC Asia Sweep + Swing BOS | FVG/OB Entry");
   Print("Sessions: London 07-10 | NY 12-15 GMT");
   Print("Risk: ", DoubleToString(InpRiskPct, 1), "% | DailyLoss: ",
         DoubleToString(InpMaxDailyLoss, 0), "% | RR 1:",
         DoubleToString(TARGET_RR, 0));
   Print("=================================================");

   if(!TerminalInfoInteger(TERMINAL_TRADE_ALLOWED)) {
      Alert("Auto trading is disabled!");
      return INIT_FAILED;
   }
   if(!MQLInfoInteger(MQL_TRADE_ALLOWED)) {
      Alert("Algo trading not allowed for this EA.");
      return INIT_FAILED;
   }

   string allSyms[] = { PAIR_EURUSD, PAIR_GBPUSD, PAIR_USDJPY, PAIR_XAUUSD, PAIR_BTCUSD };
   bool   allEnab[] = { InpTradeEURUSD, InpTradeGBPUSD, InpTradeUSDJPY, InpTradeXAUUSD, InpTradeBTCUSD };

   g_pairCount = 0;
   ArrayResize(g_pairs, 5);

   for(int i = 0; i < 5; i++) {
      if(!allEnab[i]) continue;
      string sym = allSyms[i];
      bool found = (SymbolInfoDouble(sym, SYMBOL_BID) > 0);
      if(!found) {
         string suffixes[] = { ".r", "m", ".a", ".b", ".i", ".e", ".z", ".", "_" };
         for(int s = 0; s < ArraySize(suffixes); s++) {
            string tryS = allSyms[i] + suffixes[s];
            if(SymbolInfoDouble(tryS, SYMBOL_BID) > 0) {
               sym = tryS; found = true;
               Print("Found ", allSyms[i], " as ", sym);
               break;
            }
         }
      }
      if(!found) { Print("WARNING: ", allSyms[i], " unavailable"); continue; }

      SymbolSelect(sym, true);
      g_pairs[g_pairCount].symbol        = sym;
      g_pairs[g_pairCount].active        = true;
      g_pairs[g_pairCount].engine        = new CSilverBullet(sym, InpTF, InpHTF);
      g_pairs[g_pairCount].lastTradeTime = 0;
      g_pairs[g_pairCount].lastSession   = SESSION_NONE;
      g_pairCount++;
      Print("Registered: ", sym);
   }

   if(g_pairCount == 0) { Alert("No valid pairs!"); return INIT_FAILED; }

   g_risk   = new CRiskManager(InpRiskPct, InpMaxDailyLoss, InpMaxDailyProfit,
                                20.0, InpMaxTradesDay, InpIgnoreDailyTarget);
   g_trade  = new CTradeManager(InpSlippage, InpUseBreakeven, InpUsePartial, InpUseTrail);
   g_logger = new CLogger();
   if(InpShowDashboard) g_logger.Init();

   g_lastBar = 0; g_totalTrades = 0;
   g_lastDir = SIGNAL_NONE; g_lastReason = "Waiting...";

   EventSetTimer(30);
   return INIT_SUCCEEDED;
}

void OnDeinit(const int reason) {
   if(g_logger) { g_logger.Cleanup(); delete g_logger; g_logger = NULL; }
   if(g_risk)   { delete g_risk;  g_risk  = NULL; }
   if(g_trade)  { delete g_trade; g_trade = NULL; }
   for(int i = 0; i < g_pairCount; i++) {
      if(g_pairs[i].engine) { delete g_pairs[i].engine; g_pairs[i].engine = NULL; }
   }
   EventKillTimer();
}

//============================================================
//  MAIN TICK
//============================================================

void OnTick() {
   // Emergency stop: check EVERY tick if daily loss exceeded
   if(g_risk && g_risk.CheckEmergencyStop()) {
      if(g_trade.CountPositions() > 0 || g_trade.CountPending() > 0) {
         Print("!!! DAILY LOSS LIMIT -- CLOSING ALL !!!");
         g_trade.CloseAll();
      }
      return;
   }

   bool isNewBar = false;
   for(int i = 0; i < g_pairCount; i++) {
      datetime barT = iTime(g_pairs[i].symbol, InpTF, 0);
      if(barT > 0 && barT != g_lastBar) {
         isNewBar = true; g_lastBar = barT; break;
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
         engine.ResetSession();
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
      Print("[", symbol, "] Setup blocked: ", riskReason);
      return;
   }

   SSetup setup = engine.GetSetup();

   int setupAge = (int)((TimeCurrent() - setup.setupTime) / PeriodSeconds(InpTF));
   if(setupAge > 10) {
      Print("[", symbol, "] Setup stale (", IntegerToString(setupAge), " bars)");
      return;
   }

   double lot = g_risk.CalculateLot(symbol, setup.entryPrice, setup.stopLoss);
   if(lot <= 0) return;

   bool placed = false;
   if(setup.direction == SIGNAL_BUY)
      placed = g_trade.PlaceBuyLimit(symbol, setup.entryPrice, setup.stopLoss, setup.takeProfit, lot);
   else if(setup.direction == SIGNAL_SELL)
      placed = g_trade.PlaceSellLimit(symbol, setup.entryPrice, setup.stopLoss, setup.takeProfit, lot);

   if(placed) {
      engine.OnTradePlaced();
      g_pairs[idx].lastTradeTime = TimeCurrent();
      g_totalTrades++;
      g_lastDir    = setup.direction;
      g_lastReason = setup.reason;
      g_risk.OnTradeOpened();

      if(symbol == _Symbol && InpShowDashboard) {
         g_logger.DrawFVG(symbol, setup.fvg.upper, setup.fvg.lower,
                          setup.fvg.isBullish, setup.fvg.time);
      }

      string dirStr  = (setup.direction == SIGNAL_BUY) ? "BUY" : "SELL";
      string typeStr = (setup.setupType == SETUP_ASIA_SWEEP) ? "ASIA" : "SWING";
      Print("==== ", typeStr, " ", dirStr, " ", symbol, " ====");
      Print("  E=", DoubleToString(setup.entryPrice, 5),
            " SL=", DoubleToString(setup.stopLoss, 5),
            " TP=", DoubleToString(setup.takeProfit, 5));
      Print("  ", DoubleToString(setup.slPips, 1), "p RR=1:",
            DoubleToString(setup.riskReward, 1),
            " Lot=", DoubleToString(lot, 2));
   }
}

//============================================================
//  TRADE EVENT
//============================================================

void OnTradeTransaction(const MqlTradeTransaction &trans,
                        const MqlTradeRequest &request,
                        const MqlTradeResult &result) {
   if(trans.type != TRADE_TRANSACTION_DEAL_ADD) return;
   if(!HistoryDealSelect(trans.deal)) return;

   ulong  magic = HistoryDealGetInteger(trans.deal, DEAL_MAGIC);
   if(magic != MAGIC_NUMBER) return;

   long entry = HistoryDealGetInteger(trans.deal, DEAL_ENTRY);
   if(entry != DEAL_ENTRY_OUT && entry != DEAL_ENTRY_INOUT) return;

   double profit = HistoryDealGetDouble(trans.deal, DEAL_PROFIT);
   double swap   = HistoryDealGetDouble(trans.deal, DEAL_SWAP);
   double comm   = HistoryDealGetDouble(trans.deal, DEAL_COMMISSION);
   string symbol = HistoryDealGetString(trans.deal, DEAL_SYMBOL);
   double netPnL = profit + swap + comm;

   g_risk.OnTradeClose(netPnL);

   for(int i = 0; i < g_pairCount; i++) {
      if(g_pairs[i].symbol == symbol)
         g_pairs[i].engine.OnTradeClose();
   }

   string outcome = "BE";
   if(netPnL > 0) outcome = "WIN";
   if(netPnL < 0) outcome = "LOSS";
   Print("=== CLOSED: ", symbol, " ", outcome, " $", DoubleToString(netPnL, 2),
         " Day: ", DoubleToString(g_risk.GetDayPnLPct(), 2), "%");
}

//============================================================
//  TIMER
//============================================================

void OnTimer() {
   MqlDateTime dt;
   TimeToStruct(TimeGMT(), dt);
   if(dt.hour == 0 && dt.min == 0) {
      for(int i = 0; i < g_pairCount; i++) {
         g_pairs[i].lastSession = SESSION_NONE;
         g_pairs[i].engine.ResetDay();
      }
      Print("=== DAILY RESET ===");
   }
}

//============================================================
//  DASHBOARD
//============================================================

void UpdateDashboard() {
   if(!InpShowDashboard || !g_risk || !g_logger) return;

   SAsiaLevels asia;
   ZeroMemory(asia);
   string phase = "Idle";
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
      _Symbol, session, phase,
      asia.valid ? asia.high : 0,
      asia.valid ? asia.low  : 0,
      AccountInfoDouble(ACCOUNT_BALANCE),
      g_risk.GetDayPnL(), g_risk.GetDayPnLPct(),
      g_risk.GetTradesToday(), g_risk.GetLosses(), g_risk.GetWins(),
      g_risk.GetSizeMult(), g_risk.IsTargetHit(), g_risk.IsLossHit(),
      g_lastReason, g_lastDir
   );
}
