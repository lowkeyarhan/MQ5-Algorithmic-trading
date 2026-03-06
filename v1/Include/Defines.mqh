//+------------------------------------------------------------------+
//|                                                      Defines.mqh |
//|           SMC Structure + Liquidity Sweep Scalper                |
//|                     Core Definitions v7.0                        |
//|                                                                  |
//|  v7.0: CHoCH required. H1 bias for all trades. FVG-only entry.  |
//|        Proper OB fallback. Tighter filters. Quality > quantity.  |
//+------------------------------------------------------------------+
#ifndef DEFINES_MQH
#define DEFINES_MQH

enum ENUM_SIGNAL_DIRECTION {
   SIGNAL_NONE  =  0,
   SIGNAL_BUY   =  1,
   SIGNAL_SELL  = -1
};

enum ENUM_SESSION {
   SESSION_NONE        = 0,
   SESSION_ASIA        = 1,
   SESSION_LONDON_KILL = 2,
   SESSION_NY_KILL     = 3,
   SESSION_OTHER       = 4
};

enum ENUM_SETUP_PHASE {
   PHASE_IDLE      = 0,
   PHASE_WATCHING  = 1,
   PHASE_SWEPT     = 2,
   PHASE_CONFIRMED = 3,
   PHASE_IN_TRADE  = 4,
   PHASE_DONE      = 5
};

enum ENUM_HTF_BIAS {
   BIAS_NONE    = 0,
   BIAS_BULLISH = 1,
   BIAS_BEARISH = 2
};

enum ENUM_SETUP_TYPE {
   SETUP_ASIA_SWEEP   = 0,
   SETUP_SWING_BOS    = 1
};

struct SSwingPoint {
   double   price;
   datetime time;
   int      barIndex;
   bool     isHigh;
   bool     swept;
};

struct SAsiaLevels {
   double   high;
   double   low;
   datetime highTime;
   datetime lowTime;
   bool     valid;
   bool     highSwept;
   bool     lowSwept;
   double   sweepWickTip;
   datetime sweepTime;
   datetime date;
};

struct SFVG {
   double   upper;
   double   lower;
   double   midpoint;
   bool     isBullish;
   datetime time;
   bool     active;
};

struct SSetup {
   ENUM_SIGNAL_DIRECTION direction;
   ENUM_SETUP_PHASE      phase;
   ENUM_SESSION          session;
   ENUM_SETUP_TYPE       setupType;
   double                entryPrice;
   double                stopLoss;
   double                takeProfit;
   double                riskReward;
   double                slPips;
   bool                  chochDone;
   bool                  fvgFound;
   SFVG                  fvg;
   datetime              setupTime;
   string                reason;
   double                sweepWickTip;
};

struct STradeRecord {
   ulong    ticket;
   string   symbol;
   double   openPrice;
   double   stopLoss;
   double   takeProfit;
   double   lotSize;
   datetime openTime;
   bool     breakevenSet;
   bool     partialClosed;
   double   initialRisk;
};

struct SRiskParams {
   double riskPct;
   double maxDailyLossPct;
   double maxDailyProfitPct;
   double maxDrawdownPct;
   int    maxTradesPerDay;
   double minRR;
   double marginFloor;
};

struct SStreakControl {
   int      consecutiveLosses;
   int      consecutiveWins;
   double   sizeMult;
};

//============================================================
//  CONSTANTS
//============================================================
#define EA_NAME            "SMC_ScalperEA"
#define EA_VERSION         "8.0.0"
#define MAGIC_NUMBER       20250305L

// Killzones (GMT hours)
#define LONDON_KILL_H_START  7
#define LONDON_KILL_H_END    10
#define NY_KILL_H_START      12
#define NY_KILL_H_END        15

// Asia session window (GMT)
#define ASIA_H_START   0
#define ASIA_H_END     7

// Sweep thresholds: tighter to reject noise
#define SWEEP_MIN_PIPS_FX    1.0
#define SWEEP_MIN_PIPS_JPY   0.5
#define SWEEP_MIN_PIPS_GOLD  1.0
#define SWEEP_MAX_PIPS_FX   15.0
#define SWEEP_MAX_PIPS_JPY  15.0
#define SWEEP_MAX_PIPS_GOLD 100.0

// Displacement: body >= this fraction of ATR (stricter)
#define DISP_ATR_MULT    0.7

// Minimum R:R
#define TARGET_RR        3.0

// Max SL in pips (tighter = better RR)
#define MAX_SL_PIPS_FOREX  12.0
#define MAX_SL_PIPS_JPY    12.0
#define MAX_SL_PIPS_GOLD   80.0
#define MAX_SL_PIPS_BTC    500.0

// Min SL in pips (reject noise setups)
#define MIN_SL_PIPS_FX     1.5
#define MIN_SL_PIPS_GOLD   5.0

// Asia range filter (reject too-small or too-large ranges)
#define MIN_ASIA_RANGE_FX    3.0
#define MAX_ASIA_RANGE_FX    40.0
#define MIN_ASIA_RANGE_GOLD  15.0
#define MAX_ASIA_RANGE_GOLD  150.0

// Swing detection
#define SWING_LOOKBACK     5
#define MAX_SWING_POINTS   15
#define MIN_SWING_RANGE_FX    3.0
#define MIN_SWING_RANGE_GOLD  20.0

// Streak control (gentle size reduction only)
#define LOSSES_REDUCE    4
#define LOSSES_HALF      6

// Margin floor
#define MARGIN_KILL      150.0

// Max spread (pips)
#define MAX_SPREAD_PIPS_FX   2.5
#define MAX_SPREAD_PIPS_GOLD 4.0
#define MAX_SPREAD_PIPS_BTC  50.0

// Bars after sweep to find CHoCH/FVG
#define MAX_BARS_AFTER_SWEEP 10

// Min bars between trades on same pair (= 40 min on M5)
#define MIN_BARS_BETWEEN_TRADES 8

// SL buffer beyond sweep wick
#define SL_BUFFER_PIPS_FX    1.0
#define SL_BUFFER_PIPS_GOLD  2.0

// Trade management R-multiples (v8.0: Tighter to secure wins)
#define BE_R_LEVEL       1.2
#define PARTIAL_R_LEVEL  2.0
#define PARTIAL_PCT      0.25
#define TRAIL_R_START    1.5
#define TRAIL_R_DISTANCE 1.0

// Pairs
#define PAIR_EURUSD  "EURUSD"
#define PAIR_GBPUSD  "GBPUSD"
#define PAIR_USDJPY  "USDJPY"
#define PAIR_XAUUSD  "XAUUSD"
#define PAIR_BTCUSD  "BTCUSD"

#endif
