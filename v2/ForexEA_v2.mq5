//+------------------------------------------------------------------+
//|                                               ForexEA_v2.mq5     |
//|           Institutional EA v2.2 — Sniper Execution               |
//|                                                                  |
//|  Strategy:    Multi-confluence quant system                      |
//|  Entry TF:    M5 (tick-based fast entry)                         |
//|  Bias TF:     H1 + M15 (2-vote fractal swing structure)          |
//|  Pairs:       EURUSD GBPUSD USDJPY USDCHF XAUUSD BTCUSD          |
//|  Risk:        2.5% / trade | 10% hard daily cap                  |
//|  Account:     Optimized for $20+ micro-accounts                  |
//+------------------------------------------------------------------+
#property copyright "InstEA_v2"
#property version   "2.20"
#property description "Institutional EA v2.2 | Sniper Execution | Hard TP Cap | Optimized for Micro Accounts"
#property strict

#include "Include/Defines.mqh"
#include "Include/MarketRegime.mqh"
#include "Include/OrderFlow.mqh"
#include "Include/LiquidityMap.mqh"
#include "Include/SMCEngine.mqh"
#include "Include/QuantFilter.mqh"
#include "Include/RiskManager.mqh"
#include "Include/TradeManager.mqh"
#include "Include/Dashboard.mqh"

//============================================================
//  INPUT PARAMETERS
//============================================================

input string   InpSep1         = "─── Pairs ───";
input bool     InpTradeEURUSD  = true;
input bool     InpTradeGBPUSD  = true;
input bool     InpTradeUSDJPY  = true;
input bool     InpTradeUSDCHF  = true;
input bool     InpTradeXAUUSD  = true;
input bool     InpTradeBTCUSD  = false;

input string   InpSep2         = "─── Timeframes ───";
input ENUM_TIMEFRAMES InpTF    = PERIOD_M1;    // Entry TF: M1 for scalping
input ENUM_TIMEFRAMES InpHTF   = PERIOD_M5;    // Confirmation TF: M5

input string   InpSep3         = "─── Risk ───";
input double   InpRiskPct       = 2.5;     // % risk per trade (4 losses = max daily)
input double   InpMaxDailyLoss  = 10.0;    // Hard daily loss cap % (10% max safe limit)
input double   InpMaxDailyProfit= 15.0;    // Daily profit target % (15% target)
input int      InpMaxTrades     = 10;      // Max trades per day
input bool     InpIgnoreDailyTarget = true;// For backtesting

input string   InpSep4         = "─── Trade Mgmt ───";
input bool     InpUseBreakeven = true;
input bool     InpUsePartial   = true;
input bool     InpUseTrail     = true;
input int      InpSlippage     = 10;
input int      InpLimitTimeout = 20;

input string   InpSep5         = "─── Filters ───";
input int      InpMinScore     = 30;       // Lowered slightly to allow for direct momentum triggers

input string   InpSep6         = "─── Display ───";
input bool     InpShowDashboard = true;

//============================================================
//  PAIR STATE
//============================================================

struct SPairState {
   string            symbol;
   bool              active;
   CSMCEngine       *engine;
   CMarketRegime    *regime;
   COrderFlow       *orderflow;
   CLiquidityMap    *liqmap;
   CQuantFilter     *quant;
   datetime          lastBar;
   datetime          lastSessTradeTime;
   ENUM_SESSION      lastSession;
   int               sessionTradeCount;
   bool              setupArmed;
   double            armedLot;
};

SPairState    g_pairs[];
int           g_pairCount;
CRiskManager *g_risk;
CTradeManager*g_trade;
CDashboard   *g_dash;
datetime      g_lastReset;
ENUM_SIGNAL_DIR g_lastDir    = DIR_NONE;
string          g_lastReason = "Waiting...";
int             g_lastScore  = 0;
ENUM_HTF_BIAS   g_lastBias   = BIAS_NONE;
ENUM_REGIME     g_lastRegime = REGIME_RANGING;

//============================================================
//  SYMBOL RESOLVER (handle broker suffixes)
//============================================================

string ResolveSymbol(string base) {
   if(SymbolInfoDouble(base, SYMBOL_BID) > 0) return base;
   string sfx[] = {".r","m",".a",".b",".i",".e",".z","_","."};
   for(int s = 0; s < ArraySize(sfx); s++) {
      string t = base + sfx[s];
      if(SymbolInfoDouble(t, SYMBOL_BID) > 0) {
         Print("Resolved ", base, " → ", t);
         return t;
      }
   }
   return "";
}

//============================================================
//  INITIALISATION
//============================================================

int OnInit() {
   Print("═══════════════════════════════════════════");
   Print(EA_NAME_V2, " v", EA_VERSION_V2, " STARTING");
   Print("Strategy: SMC+OrderFlow+LiqMap+QuantFilter Sniper");
   Print("Risk: ", DoubleToString(InpRiskPct,1), "% | DailyLoss: ",
         DoubleToString(InpMaxDailyLoss,0), "% | MinScore: ", InpMinScore);
   Print("═══════════════════════════════════════════");

   if(!TerminalInfoInteger(TERMINAL_TRADE_ALLOWED)) {
      Alert("Auto-trading is disabled!"); return INIT_FAILED;
   }
   if(!MQLInfoInteger(MQL_TRADE_ALLOWED)) {
      Alert("EA trading not allowed!"); return INIT_FAILED;
   }

   string bases[] = { PAIR_EURUSD, PAIR_GBPUSD, PAIR_USDJPY, PAIR_USDCHF, PAIR_XAUUSD, PAIR_BTCUSD };
   bool   enab[]  = { InpTradeEURUSD, InpTradeGBPUSD, InpTradeUSDJPY, InpTradeUSDCHF, InpTradeXAUUSD, InpTradeBTCUSD };

   g_pairCount = 0;
   ArrayResize(g_pairs, 6);
   for(int i = 0; i < 6; i++) {
      if(!enab[i]) continue;
      string sym = ResolveSymbol(bases[i]);
      if(sym == "") { Print("WARNING: ", bases[i], " unavailable"); continue; }
      SymbolSelect(sym, true);
      g_pairs[g_pairCount].symbol             = sym;
      g_pairs[g_pairCount].active             = true;
      g_pairs[g_pairCount].engine             = new CSMCEngine(sym, InpTF, InpHTF);
      g_pairs[g_pairCount].regime             = new CMarketRegime(sym);
      g_pairs[g_pairCount].orderflow          = new COrderFlow(sym);
      g_pairs[g_pairCount].liqmap             = new CLiquidityMap(sym);
      g_pairs[g_pairCount].quant              = new CQuantFilter(sym);
      g_pairs[g_pairCount].lastBar            = 0;
      g_pairs[g_pairCount].lastSessTradeTime  = 0;
      g_pairs[g_pairCount].lastSession        = SESSION_NONE;
      g_pairs[g_pairCount].sessionTradeCount  = 0;
      g_pairs[g_pairCount].setupArmed         = false;
      g_pairs[g_pairCount].armedLot           = 0;
      g_pairCount++;
      Print("Registered: ", sym);
   }

   if(g_pairCount == 0) { Alert("No valid pairs!"); return INIT_FAILED; }

   g_risk  = new CRiskManager(InpRiskPct, InpMaxDailyLoss, InpMaxDailyProfit,
                               InpMaxTrades, InpIgnoreDailyTarget, MAGIC_NUMBER_V2);
   g_trade = new CTradeManager(InpSlippage, InpUseBreakeven, InpUsePartial,
                               InpUseTrail, MAGIC_NUMBER_V2);
   g_dash  = new CDashboard();
   if(InpShowDashboard) g_dash.Init();

   g_lastReset = 0;
   EventSetTimer(60);
   return INIT_SUCCEEDED;
}

//============================================================
//  DEINIT
//============================================================

void OnDeinit(const int reason) {
   if(g_dash)  { g_dash.Cleanup(); delete g_dash;  g_dash  = NULL; }
   if(g_risk)  { delete g_risk;  g_risk  = NULL; }
   if(g_trade) { delete g_trade; g_trade = NULL; }
   for(int i = 0; i < g_pairCount; i++) {
      if(g_pairs[i].engine)    { delete g_pairs[i].engine;    g_pairs[i].engine    = NULL; }
      if(g_pairs[i].regime)    { delete g_pairs[i].regime;    g_pairs[i].regime    = NULL; }
      if(g_pairs[i].orderflow) { delete g_pairs[i].orderflow; g_pairs[i].orderflow = NULL; }
      if(g_pairs[i].liqmap)    { delete g_pairs[i].liqmap;    g_pairs[i].liqmap    = NULL; }
      if(g_pairs[i].quant)     { delete g_pairs[i].quant;     g_pairs[i].quant     = NULL; }
   }
   EventKillTimer();
}

//============================================================
//  DAILY RESET
//============================================================

void CheckDailyReset() {
   MqlDateTime dt; TimeToStruct(TimeCurrent(), dt);
   dt.hour = 0; dt.min = 0; dt.sec = 0;
   datetime today = StructToTime(dt);
   if(g_lastReset == today) return;
   g_lastReset = today;
   for(int i = 0; i < g_pairCount; i++) {
      g_pairs[i].engine.ResetDay();
      g_pairs[i].sessionTradeCount = 0;
      g_pairs[i].lastSession       = SESSION_NONE;
      g_pairs[i].setupArmed        = false;
   }
   g_lastDir    = DIR_NONE;
   g_lastReason = "Waiting...";
   Print("═══ DAILY RESET ═══");
}

//============================================================
//  SESSION RESET
//============================================================

void CheckSessionReset(int idx) {
   ENUM_SESSION curSes = CMarketRegime::GetSession();
   if(curSes == g_pairs[idx].lastSession) return;
   g_pairs[idx].lastSession      = curSes;
   g_pairs[idx].sessionTradeCount = 0;
   g_pairs[idx].engine.ResetSession();
   g_pairs[idx].setupArmed = false;
}

//============================================================
//  CORRELATION CHECK HELPER
//============================================================

bool IsCorrelated(string symbol, ENUM_SIGNAL_DIR dir) {
   string openSyms[10]; ENUM_SIGNAL_DIR openDirs[10];
   int cnt = 0;
   for(int i = PositionsTotal() - 1; i >= 0 && cnt < 10; i--) {
      ulong t = PositionGetTicket(i);
      if(t == 0) continue;
      if((ulong)PositionGetInteger(POSITION_MAGIC) != MAGIC_NUMBER_V2) continue;
      openSyms[cnt] = PositionGetString(POSITION_SYMBOL);
      openDirs[cnt] = ((ENUM_POSITION_TYPE)PositionGetInteger(POSITION_TYPE) == POSITION_TYPE_BUY) ? DIR_BUY : DIR_SELL;
      cnt++;
   }
   for(int i = 0; i < g_pairCount; i++) {
      if(g_pairs[i].quant != NULL)
         return g_pairs[i].quant.IsCorrelationBlocked(symbol, dir, openSyms, openDirs, cnt);
   }
   return false;
}

//============================================================
//  PROCESS SINGLE PAIR ON EACH TICK
//============================================================

bool TryTickEntry(int idx) {
   if(!g_pairs[idx].setupArmed) return false;
   SConfluenceSetup setup = g_pairs[idx].engine.GetSetup();
   if(setup.phase != PHASE_CONFIRMED) { g_pairs[idx].setupArmed = false; return false; }
   if(setup.entryFired) return false;

   int ageBars = (int)((TimeCurrent() - setup.setupTime) / PeriodSeconds(InpTF));
   if(ageBars > SETUP_MAX_AGE_BARS) {
      Print("[", g_pairs[idx].symbol, "] Setup expired (", ageBars, " bars)");
      g_pairs[idx].engine.InvalidateSetup();
      g_pairs[idx].setupArmed = false;
      return false;
   }

   if(g_pairs[idx].armedLot <= 0) return false;
   double lot = g_pairs[idx].armedLot;

   bool placed = g_trade.CheckTickEntry(
      g_pairs[idx].symbol,
      setup.direction,
      setup.entryPrice,
      setup.stopLoss,
      setup.takeProfit,
      lot
   );
   if(placed) {
      g_pairs[idx].engine.OnTradePlaced();
      g_pairs[idx].setupArmed = false;
      g_pairs[idx].sessionTradeCount++;
      g_risk.OnTradeOpened();
      g_lastDir    = setup.direction;
      g_lastReason = setup.reason;

      if(g_pairs[idx].symbol == _Symbol && InpShowDashboard)
         g_dash.DrawFVG(g_pairs[idx].symbol, setup.fvg.upper, setup.fvg.lower,
                        setup.fvg.isBullish, setup.fvg.time);
      return true;
   }
   return false;
}

//============================================================
//  PROCESS SINGLE PAIR — NEW BAR LOGIC
//============================================================

void ProcessPairNewBar(int idx) {
   string sym     = g_pairs[idx].symbol;
   ENUM_SESSION ses = CMarketRegime::GetSession();

   if(g_pairs[idx].sessionTradeCount >= 3) return;
   if(g_trade.CountPositions(sym) > 0) return;
   if(g_trade.CountPending(sym) > 0)   return;
   
   string riskReason;
   if(!g_risk.CanTrade(riskReason)) {
      if(g_pairs[idx].engine.HasSetup()) g_pairs[idx].engine.InvalidateSetup();
      g_pairs[idx].setupArmed = false;
      return;
   }

   g_pairs[idx].regime.Update();
   SMarketRegime mr = g_pairs[idx].regime.GetRegime();
   if(mr.regime == REGIME_CHOPPY) return;

   g_pairs[idx].liqmap.Update(InpHTF);
   bool setupReady = g_pairs[idx].engine.Update(ses);
   if(!setupReady) return;

   SConfluenceSetup setup = g_pairs[idx].engine.GetSetup();
   SOrderFlowData of = g_pairs[idx].orderflow.Scan(
      InpTF,
      setup.sweepWickTip,
      (setup.direction == DIR_SELL),   
      setup.direction
   );
   
   int liqBonus = g_pairs[idx].liqmap.ProximityBonus(setup.entryPrice, setup.direction, 10.0);
   bool inDiscount = g_pairs[idx].liqmap.IsInDiscount(PERIOD_H1, 60);
   
   int score = g_pairs[idx].quant.ScoreConfluence(setup, mr, of, liqBonus, inDiscount);
   g_pairs[idx].engine.SetScore(score);
   
   if(score < InpMinScore) {
      Print("[", sym, "] Score too low: ", score, "/100 (min ", InpMinScore, ")");
      return;
   }

   if(IsCorrelated(sym, setup.direction)) {
      Print("[", sym, "] Correlation blocked");
      return;
   }

   double lot = g_risk.CalculateLot(sym, setup.entryPrice, setup.stopLoss);
   if(lot <= 0) { g_pairs[idx].engine.InvalidateSetup(); return; }

   g_pairs[idx].setupArmed = true;
   g_pairs[idx].armedLot   = lot;
   g_lastScore  = score;
   g_lastBias   = mr.bias;
   g_lastRegime = mr.regime;
   Print("[", sym, "] SETUP ARMED | Score=", score, " Bias=", EnumToString(mr.bias),
         " Dir=", (setup.direction == DIR_BUY ? "BUY" : "SELL"),
         " E=", DoubleToString(setup.entryPrice, (int)SymbolInfoInteger(sym, SYMBOL_DIGITS)),
         " SL=", DoubleToString(setup.slPips, 1), "p RR=1:",
         DoubleToString(setup.riskReward, 1), " Lot=", DoubleToString(lot, 2));
         
   if(sym == _Symbol && InpShowDashboard) {
      SAsiaLevels asia = g_pairs[idx].engine.GetAsiaLevels();
      if(asia.valid) g_dash.DrawAsiaLevels(sym, asia.high, asia.low);
   }
}

//============================================================
//  ON TICK — CORE LOOP
//============================================================

void OnTick() {
   CheckDailyReset();
   bool capBreached = g_risk.Update();
   if(capBreached) {
      g_trade.CloseAll();
      return;
   }

   g_trade.ManagePositions();
   
   for(int i = 0; i < g_pairCount; i++) {
      if(!g_pairs[i].active) continue;
      if(g_pairs[i].setupArmed) TryTickEntry(i);
   }

   for(int i = 0; i < g_pairCount; i++) {
      if(!g_pairs[i].active) continue;
      datetime barT = iTime(g_pairs[i].symbol, InpTF, 0);
      if(barT == 0 || barT == g_pairs[i].lastBar) continue;
      g_pairs[i].lastBar = barT;
      g_trade.CancelStaleLimits(InpLimitTimeout);
      CheckSessionReset(i);
      ProcessPairNewBar(i);
   }

   if(InpShowDashboard) {
      string session = CMarketRegime::SessionName(CMarketRegime::GetSession());
      g_dash.Update(
         _Symbol, session,
         g_lastBias, g_lastRegime,
         AccountInfoDouble(ACCOUNT_BALANCE),
         g_risk.GetDayPnL(), g_risk.GetDayPnLPct(),
         g_risk.GetTradesOpened(),
         g_risk.GetLosses(), g_risk.GetWins(),
         g_risk.GetSizeMult(),
         g_risk.IsLossHit(),
         g_lastReason, g_lastDir, g_lastScore
      );
   }
}

//============================================================
//  TRADE CLOSE EVENT
//============================================================

void OnTradeTransaction(const MqlTradeTransaction &trans,
                        const MqlTradeRequest &request,
                        const MqlTradeResult  &result) {
   if(trans.type != TRADE_TRANSACTION_DEAL_ADD) return;
   if(!HistoryDealSelect(trans.deal)) return;
   if((ulong)HistoryDealGetInteger(trans.deal, DEAL_MAGIC) != MAGIC_NUMBER_V2) return;

   long entry = HistoryDealGetInteger(trans.deal, DEAL_ENTRY);
   if(entry != DEAL_ENTRY_OUT && entry != DEAL_ENTRY_INOUT) return;
   double profit  = HistoryDealGetDouble(trans.deal, DEAL_PROFIT);
   double swap    = HistoryDealGetDouble(trans.deal, DEAL_SWAP);
   double comm    = HistoryDealGetDouble(trans.deal, DEAL_COMMISSION);
   string symbol  = HistoryDealGetString(trans.deal, DEAL_SYMBOL);
   double netPnL  = profit + swap + comm;

   g_risk.OnTradeClose(netPnL);
   for(int i = 0; i < g_pairCount; i++) {
      if(g_pairs[i].symbol == symbol) {
         g_pairs[i].engine.OnTradeClose();
         g_pairs[i].setupArmed = false;
      }
   }

   string outcome = (netPnL > 0) ? "WIN" : (netPnL < 0 ? "LOSS" : "BE");
   Print("═══ CLOSED: ", symbol, " ", outcome, " $", DoubleToString(netPnL, 2),
         " | Day: ", DoubleToString(g_risk.GetDayPnLPct(), 2), "%");
}

//============================================================
//  TIMER
//============================================================

void OnTimer() {
   MqlDateTime dt;
   TimeToStruct(TimeGMT(), dt);
   if(dt.hour == 0 && dt.min < 2) {
      for(int i = 0; i < g_pairCount; i++) {
         g_pairs[i].engine.ResetDay();
         g_pairs[i].sessionTradeCount = 0;
      }
   }
}