//+------------------------------------------------------------------+
//|                                                   ForexEA.mq5   |
//|              SMC Structure + Liquidity Sweep Scalper v4.0       |
//|                                                                  |
//|  Strategy: Map Asia H/L -> Wait for killzone sweep ->           |
//|            Detect CHoCH + OB/FVG -> Place limit at OB/FVG ->    |
//|            SL beyond structure -> TP = liquidity target 1:3 min |
//|                                                                  |
//|  Sessions: London 07:00-10:00 GMT + NY 12:00-15:00 GMT         |
//|  Pairs:    EURUSD, GBPUSD, USDJPY, XAUUSD                      |
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

input string InpSep1 = "--- Pairs ---"; // ===== PAIRS =====
input bool InpTradeEURUSD = true; // Trade EURUSD
input bool InpTradeGBPUSD = true; // Trade GBPUSD
input bool InpTradeUSDJPY = true; // Trade USDJPY
input bool InpTradeXAUUSD = true; // Trade XAUUSD(Gold)
input bool InpTradeBTCUSD = false; // Trade BTCUSD

input string InpSep2 = "--- Timeframes ---"; // ===== TIMEFRAMES =====
input ENUM_TIMEFRAMES InpTF = PERIOD_M5; // Entry Timeframe
input ENUM_TIMEFRAMES InpHTF = PERIOD_M15; // Structure Timeframe

input string InpSep3 = "--- Risk ---"; // ===== RISK =====
input double InpRiskPct = 2.0; // Risk % per trade
input double InpMaxDailyLoss = 6.0; // Max daily loss %
input double InpMaxDailyProfit = 10.0; // Daily profit target %
input double InpMaxDrawdown = 20.0; // Max total drawdown %
input int InpMaxTradesDay = 4; // Max trades per day

input string InpSep4 = "--- Trade Mgmt ---"; // ===== TRADE MGMT =====
input bool InpUseBreakeven = true; // Breakeven at 1R
input bool InpUsePartial = true; // Close 50 % at 1.5R
input bool InpUseTrail = true; // Trail after 2R
input int InpLimitTimeout = 25; // Cancel unfilled limit(minutes)
input int InpSlippage = 15; // Max slippage(points)

input string InpSep5 = "--- Display ---"; // ===== DISPLAY =====
input bool InpShowDashboard = true; // Show on - chart dashboard

//============================================================
//  GLOBAL OBJECTS
//============================================================

struct SPairState {
    string symbol;
    bool active;
    CSilverBullet * engine;
    datetime lastTradeTime;
    int tradesThisSession;
    ENUM_SESSION lastSession;
};

SPairState g_pairs[];
int g_pairCount;
CRiskManager * g_risk;
CTradeManager * g_trade;
CLogger * g_logger;
datetime g_lastBar;
int g_totalTrades;
ENUM_SIGNAL_DIRECTION g_lastDir;
string g_lastReason;

//============================================================
//  INITIALIZATION
//============================================================

int OnInit() {
    Print("=================================================");
    Print(StringFormat(" % s v % s STARTING", EA_NAME, EA_VERSION));
    Print("Strategy: SMC Liquidity Sweep + CHoCH + OB / FVG | 1:3 RR min");
    Print("Sessions: London 07:00 - 10:00 | NY 12:00 - 15:00 GMT");
    Print("=================================================");

    if(!TerminalInfoInteger(TERMINAL_TRADE_ALLOWED)) {
        Alert("Auto trading is disabled! Enable it in MT5.");
        return INIT_FAILED;
    }

    if(!MQLInfoInteger(MQL_TRADE_ALLOWED)) {
        Alert("Algo trading not allowed for this EA. Check settings.");
        return INIT_FAILED;
    }

    string allSyms[] = { PAIR_EURUSD, PAIR_GBPUSD, PAIR_USDJPY, PAIR_XAUUSD, PAIR_BTCUSD };
        bool allEnab[] = { InpTradeEURUSD, InpTradeGBPUSD, InpTradeUSDJPY, InpTradeXAUUSD, InpTradeBTCUSD };

            g_pairCount = 0;
            ArrayResize(g_pairs, 5);

            for(int i = 0; i < 5; i++) {
                if(!allEnab[i]) continue;

      // Try both with and without suffix (some brokers use EURUSD.r, EURUSDm, etc.)
                string sym = allSyms[i];
                bool found = (SymbolInfoDouble(sym, SYMBOL_BID) > 0);

                if(!found) {
         // Try common suffixes
                    string suffixes[] = { ".r", "m", ".a", ".b", ".i", ".e", ".z", ".", "_" };
                        for(int s = 0; s < ArraySize(suffixes); s++) {
                            string trySymbol = allSyms[i] + suffixes[s];
                            if(SymbolInfoDouble(trySymbol, SYMBOL_BID) > 0) {
                                sym = trySymbol;
                                found = true;
                                Print(StringFormat("Found % s as % s", allSyms[i], sym));
                                break;
                            }
                        }
                    }

                    if(!found) {
                        Print(StringFormat("WARNING: % s not available - skipping", allSyms[i]));
                        continue;
                    }

      // Make sure symbol is in Market Watch
                    SymbolSelect(sym, true);

                    g_pairs[g_pairCount].symbol = sym;
                    g_pairs[g_pairCount].active = true;
                    g_pairs[g_pairCount].engine = new CSilverBullet(sym, InpTF, InpHTF);
                    g_pairs[g_pairCount].lastTradeTime = 0;
                    g_pairs[g_pairCount].tradesThisSession = 0;
                    g_pairs[g_pairCount].lastSession = SESSION_NONE;
                    g_pairCount++;
                    Print(StringFormat("Pair registered: % s(bid = % .5f)", sym, SymbolInfoDouble(sym, SYMBOL_BID)));
                }

                if(g_pairCount == 0) {
                    Alert("No valid pairs! Enable at least one pair.");
                    return INIT_FAILED;
                }

                g_risk = new CRiskManager(InpRiskPct, InpMaxDailyLoss, InpMaxDailyProfit,
                InpMaxDrawdown, InpMaxTradesDay);
                g_trade = new CTradeManager(InpSlippage, InpUseBreakeven, InpUsePartial, InpUseTrail);
                g_logger = new CLogger();
                if(InpShowDashboard) g_logger.Init();

                g_lastBar = 0;
                g_totalTrades = 0;
                g_lastDir = SIGNAL_NONE;
                g_lastReason = "Waiting for killzone...";

                Print(StringFormat("Initialized: % d pairs | Risk = % .1f % % | Target = % .1f % % | MaxLoss = % .1f % %",
                g_pairCount, InpRiskPct, InpMaxDailyProfit, InpMaxDailyLoss));

   // Detect GMT offset
                datetime gmt = TimeGMT();
                datetime srv = TimeCurrent();
                int offset = (int)(srv - gmt);
                Print(StringFormat("Broker time offset: UTC % + d hours", offset / 3600));

                EventSetTimer(30);
                return INIT_SUCCEEDED;
            }

//============================================================
//  DEINITIALIZATION
//============================================================

            void OnDeinit(const int reason) {
                if(g_logger) { g_logger.Cleanup(); delete g_logger; g_logger = NULL; }
                    if(g_risk) { delete g_risk; g_risk = NULL; }
                        if(g_trade) { delete g_trade; g_trade = NULL; }

                            for(int i = 0; i < g_pairCount; i++) {
                                if(g_pairs[i].engine) { delete g_pairs[i].engine; g_pairs[i].engine = NULL; }
                                }
                                EventKillTimer();
                                Print(EA_NAME + " deinitialized. Reason: " + IntegerToString(reason));
                            }

//============================================================
//  MAIN TICK
//============================================================

                            void OnTick() {
   // Process on new M5 bar (use a pair's bar time, not just _Symbol)
                                bool isNewBar = false;
                                for(int i = 0; i < g_pairCount; i++) {
                                    datetime barT = iTime(g_pairs[i].symbol, InpTF, 0);
                                    if(barT > 0 && barT != g_lastBar) {
                                        isNewBar = true;
                                        g_lastBar = barT;
                                        break;
                                    }
                                }

   // Always manage open positions every tick
                                if(g_trade) g_trade.ManagePositions();

                                if(!isNewBar) return;

   // Cancel stale pending orders
                                g_trade.CancelStaleLimits(InpLimitTimeout);

   // Update risk state
                                g_risk.Update();

                                string riskReason;
                                bool canTrade = g_risk.CanTrade(riskReason);

   // Process each pair
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
                                CSilverBullet * engine = g_pairs[idx].engine;
                                string symbol = g_pairs[idx].symbol;

   // Detect session change -> reset per-session counter
                                ENUM_SESSION currentSes = engine.GetSession();
                                if(currentSes != g_pairs[idx].lastSession) {
                                    if(currentSes == SESSION_LONDON_KILL || currentSes == SESSION_NY_KILL) {
                                        g_pairs[idx].tradesThisSession = 0;
                                        engine.ResetSession();
                                        Print(StringFormat("[ % s] New session: % s - counters reset", symbol, engine.GetSessionName()));
                                    }
                                    g_pairs[idx].lastSession = currentSes;
                                }

   // Run strategy engine
                                bool setupReady = engine.Update();

   // Draw Asia levels on chart
                                if(symbol == _Symbol && InpShowDashboard) {
                                    SAsiaLevels asia = engine.GetAsiaLevels();
                                    if(asia.valid) g_logger.DrawAsiaLevels(symbol, asia.high, asia.low);
                                }

   // Skip if we already have a position or pending on this pair
                                if(g_trade.CountPositions(symbol) > 0) return;
                                if(g_trade.CountPending(symbol) > 0) return;

                                if(!setupReady) return;

                                if(!canTrade) {
                                    Print(StringFormat("[ % s] Setup ready but blocked: % s", symbol, riskReason));
                                    return;
                                }

   // Allow 2 trades per killzone session per pair
                                if(g_pairs[idx].tradesThisSession >= 2) {
                                    Print(StringFormat("[ % s] Already traded 2x this session", symbol));
                                    return;
                                }

                                SSetup setup = engine.GetSetup();

   // Validate setup is still fresh (not older than 10 bars)
                                int setupAge = (int)((TimeCurrent() - setup.setupTime) / PeriodSeconds(InpTF));
                                if(setupAge > 10) {
                                    Print(StringFormat("[ % s] Setup too old( % d bars), skipping", symbol, setupAge));
                                    return;
                                }

                                double lot = g_risk.CalculateLot(symbol, setup.entryPrice, setup.stopLoss);
                                if(lot <= 0) {
                                    Print(StringFormat("[ % s] Lot calculation failed or zero", symbol));
                                    return;
                                }

                                bool placed = false;
                                if(setup.direction == SIGNAL_BUY) {
                                    placed = g_trade.PlaceBuyLimit(symbol, setup.entryPrice, setup.stopLoss, setup.takeProfit, lot);
                                } else if (setup.direction == SIGNAL_SELL) {
                                    placed = g_trade.PlaceSellLimit(symbol, setup.entryPrice, setup.stopLoss, setup.takeProfit, lot);
                                }

                                if(placed) {
                                    engine.OnTradePlaced();
                                    g_pairs[idx].tradesThisSession++;
                                    g_pairs[idx].lastTradeTime = TimeCurrent();
                                    g_totalTrades++;
                                    g_lastDir = setup.direction;
                                    g_lastReason = setup.reason;
                                    g_risk.OnTradeOpened();

                                    if(symbol == _Symbol && InpShowDashboard) {
                                        g_logger.DrawFVG(symbol, setup.fvg.upper, setup.fvg.lower,
                                        setup.fvg.isBullish, setup.fvg.time);
                                        SAsiaLevels asia = engine.GetAsiaLevels();
                                        g_logger.DrawSweepArrow(symbol, setup.direction == SIGNAL_BUY,
                                        asia.sweepWickTip, asia.sweepTime);
                                    }

                                    Print("====================================");
                                    Print(StringFormat(" ORDER PLACED: % s % s", symbol,
                                    setup.direction == SIGNAL_BUY ? "BUY" : "SELL"));
                                    Print(StringFormat(" Entry : % .5f", setup.entryPrice));
                                    Print(StringFormat(" SL : % .5f( % .1f pips)", setup.stopLoss, setup.slPips));
                                    Print(StringFormat(" TP : % .5f(RR 1: % .1f)", setup.takeProfit, setup.riskReward));
                                    Print(StringFormat(" Lot : % .2f", lot));
                                    Print(StringFormat(" Session: % s", setup.session == SESSION_LONDON_KILL
                                    ? "London Killzone" : "NY Killzone"));
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
                                    ulong magic = HistoryDealGetInteger(trans.deal, DEAL_MAGIC);
                                    double profit = HistoryDealGetDouble(trans.deal, DEAL_PROFIT);
                                    double swap = HistoryDealGetDouble(trans.deal, DEAL_SWAP);
                                    double comm = HistoryDealGetDouble(trans.deal, DEAL_COMMISSION);
                                    long entry = HistoryDealGetInteger(trans.deal, DEAL_ENTRY);
                                    string symbol = HistoryDealGetString(trans.deal, DEAL_SYMBOL);

                                    if(magic != MAGIC_NUMBER) return;
                                    if(entry != DEAL_ENTRY_OUT && entry != DEAL_ENTRY_INOUT) return;

                                    double netPnL = profit + swap + comm;
                                    g_risk.OnTradeClose(netPnL);

                                    for(int i = 0; i < g_pairCount; i++) {
                                        if(g_pairs[i].symbol == symbol) {
                                            g_pairs[i].engine.OnTradeClose();
                                        }
                                    }

                                    string outcome = (netPnL > 0) ? "WIN" : (netPnL < 0) ? "LOSS" : "BE";
                                    Print(StringFormat("=== TRADE CLOSED: % s % s $ % .2f | Day: % + .2f % %",
                                    symbol, outcome, netPnL, g_risk.GetDayPnLPct()));
                                }
                            }

//============================================================
//  TIMER — session resets and daily cleanup
//============================================================

                            void OnTimer() {
                                MqlDateTime dt;
                                TimeToStruct(TimeGMT(), dt);

   // Daily reset at midnight GMT
                                if(dt.hour == 0 && dt.min == 0) {
                                    for(int i = 0; i < g_pairCount; i++) {
                                        g_pairs[i].tradesThisSession = 0;
                                        g_pairs[i].lastSession = SESSION_NONE;
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
                                string phase = "Idle";
                                string session = "Off - Session";

                                for(int i = 0; i < g_pairCount; i++) {
                                    if(g_pairs[i].symbol == _Symbol) {
                                        asia = g_pairs[i].engine.GetAsiaLevels();
                                        phase = EnumToString(g_pairs[i].engine.GetSetup().phase);
                                        session = g_pairs[i].engine.GetSessionName();
                                        break;
                                    }
                                }

                                g_logger.UpdateDashboard(
                                _Symbol,
                                session,
                                phase,
                                asia.valid ? asia.high : 0,
                                asia.valid ? asia.low : 0,
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
