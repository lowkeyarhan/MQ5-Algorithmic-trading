//+------------------------------------------------------------------+
//|                                                      Defines.mqh |
//|           SMC Structure + Liquidity Sweep Scalper                |
//|                     Core Definitions v6.0                        |
//+------------------------------------------------------------------+
#ifndef DEFINES_MQH
#define DEFINES_MQH

enum ENUM_SIGNAL_DIRECTION {
   SIGNAL_NONE  =  0,
   SIGNAL_BUY   =  1,
   SIGNAL_SELL  = -1
};

enum ENUM_EA_STATE {
   STATE_NORMAL    = 0,
   STATE_REDUCED   = 1,
   STATE_PAUSED    = 2,
   STATE_RECOVERY  = 3
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
#define EA_VERSION         "6.0.0"
#define MAGIC_NUMBER       20250305L

// Killzones (GMT hours)
#define LONDON_KILL_H_START  7
#define LONDON_KILL_H_END    10
#define NY_KILL_H_START      12
#define NY_KILL_H_END        15

// Asia session window (GMT)
#define ASIA_H_START   0
#define ASIA_H_END     7

// Sweep minimums per instrument class
#define SWEEP_MIN_PIPS_FX    0.5
#define SWEEP_MIN_PIPS_JPY   0.3
#define SWEEP_MIN_PIPS_GOLD  0.3
#define SWEEP_MAX_PIPS_FX   25.0
#define SWEEP_MAX_PIPS_JPY  25.0
#define SWEEP_MAX_PIPS_GOLD 300.0

// Displacement body >= this fraction of ATR
#define DISP_ATR_MULT    0.5

// Minimum R:R
#define TARGET_RR        3.0

// Max SL in pips
#define MAX_SL_PIPS_FOREX  15.0
#define MAX_SL_PIPS_JPY    15.0
#define MAX_SL_PIPS_GOLD   150.0
#define MAX_SL_PIPS_BTC    500.0

// Min SL in pips (reject noise setups)
#define MIN_SL_PIPS_FX     1.0
#define MIN_SL_PIPS_GOLD   3.0

// Swing detection: N bars required on each side
#define SWING_LOOKBACK     4

// Max swing points to track
#define MAX_SWING_POINTS   20

// Minimum swing significance in pips
#define MIN_SWING_RANGE_FX    2.0
#define MIN_SWING_RANGE_GOLD  10.0

// Streak: reduce size after this many consecutive losses (NO pausing)
#define LOSSES_REDUCE    4
#define LOSSES_HALF      6

// Margin floor
#define MARGIN_KILL      150.0

// Max spread (pips)
#define MAX_SPREAD_PIPS_FX   3.0
#define MAX_SPREAD_PIPS_GOLD 5.0
#define MAX_SPREAD_PIPS_BTC  50.0

// Bars after sweep to find CHoCH/FVG
#define MAX_BARS_AFTER_SWEEP 12

// Min bars between trades on same pair
#define MIN_BARS_BETWEEN_TRADES 5

// Trade management R-multiples
#define BE_R_LEVEL       1.3
#define PARTIAL_R_LEVEL  2.0
#define PARTIAL_PCT      0.40
#define TRAIL_R_START    2.5

// Pairs
#define PAIR_EURUSD  "EURUSD"
#define PAIR_GBPUSD  "GBPUSD"
#define PAIR_USDJPY  "USDJPY"
#define PAIR_XAUUSD  "XAUUSD"
#define PAIR_BTCUSD  "BTCUSD"

#endif
