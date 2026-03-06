//+------------------------------------------------------------------+
//|                                                    Defines.mqh   |
//|           Institutional EA v2 — Core Definitions                 |
//|  All enums, structs and constants shared across modules          |
//+------------------------------------------------------------------+
#ifndef DEFINES_V2_MQH
#define DEFINES_V2_MQH

//============================================================
//  ENUMS
//============================================================

enum ENUM_SIGNAL_DIR {
   DIR_NONE  =  0,
   DIR_BUY   =  1,
   DIR_SELL  = -1
};

enum ENUM_HTF_BIAS {
   BIAS_NONE     = 0,
   BIAS_BULLISH  = 1,
   BIAS_BEARISH  = 2,
   BIAS_CONFLICT = 3
};

enum ENUM_REGIME {
   REGIME_TRENDING_UP   = 0,
   REGIME_TRENDING_DOWN = 1,
   REGIME_RANGING       = 2,
   REGIME_CHOPPY        = 3   // skip all trades
};

enum ENUM_VOLATILITY {
   VOL_LOW     = 0,
   VOL_NORMAL  = 1,
   VOL_HIGH    = 2,
   VOL_EXTREME = 3
};

enum ENUM_SESSION {
   SESSION_NONE      = 0,
   SESSION_SYDNEY    = 1,
   SESSION_ASIA      = 2,     // Tokyo 00:00-06:00 GMT
   SESSION_LONDON    = 3,     // 07:00-10:00 GMT
   SESSION_NY        = 4,     // 12:00-15:00 GMT
   SESSION_LONDON_NY = 5,     // 12:00-14:00 GMT overlap
   SESSION_OTHER     = 6
};

enum ENUM_FVG_GRADE {
   FVG_NONE = 0,
   FVG_C    = 1,   // weak — skip
   FVG_B    = 2,   // decent
   FVG_A    = 3    // strongest
};

enum ENUM_SETUP_PHASE {
   PHASE_IDLE      = 0,
   PHASE_WATCHING  = 1,
   PHASE_SWEPT     = 2,
   PHASE_CONFIRMED = 3,
   PHASE_ARMED     = 4,  // price approaching entry — ready to fire
   PHASE_IN_TRADE  = 5,
   PHASE_DONE      = 6
};

enum ENUM_TRAIL_PHASE {
   TRAIL_NONE    = 0,
   TRAIL_PHASE1  = 1,   // 1.0R–1.5R: 1.2×ATR
   TRAIL_PHASE2  = 2,   // 1.5R–3.0R: 0.8×ATR
   TRAIL_PHASE3  = 3    // >3.0R:     0.5×ATR
};

//============================================================
//  STRUCTS
//============================================================

struct SSwingPoint {
   double   price;
   datetime time;
   int      barIndex;
   bool     isHigh;
   bool     swept;
   int      touchCount;
};

struct SAsiaLevels {
   double   high;
   double   low;
   datetime highTime;
   datetime lowTime;
   datetime date;
   bool     valid;
   bool     highSwept;
   bool     lowSwept;
};

struct SFVG {
   double        upper;
   double        lower;
   double        midpoint;
   bool          isBullish;
   datetime      time;
   bool          active;
   ENUM_FVG_GRADE grade;
   int           touchCount;
   double        displacementBody;  // body size of displacement candle (quality signal)
};

struct SLiquidityPool {
   double   price;
   bool     isBuyStop;    // true = buy-stop cluster above (equal highs)
   int      touchCount;
   int      ageInBars;
   double   score;        // 0–100
   datetime time;
   bool     active;
};

struct SOrderFlowData {
   double   cumulativeDelta;    // approximate buy-sell pressure
   bool     absorptionDetected;
   bool     imbalanceDetected;
   bool     stopHuntBarDetected;
   bool     volumeDivergence;
   double   dominantDelta;      // last N bars net delta
};

struct SMarketRegime {
   ENUM_REGIME      regime;
   ENUM_VOLATILITY  volatility;
   ENUM_HTF_BIAS    bias;       // 3-TF consensus bias
   bool             biasStrong; // all 3 TFs agree
};

struct SConfluenceSetup {
   ENUM_SIGNAL_DIR   direction;
   ENUM_SETUP_PHASE  phase;
   ENUM_SESSION      session;
   double            entryPrice;
   double            stopLoss;
   double            takeProfit;
   double            riskReward;
   double            slPips;
   SFVG              fvg;
   double            sweepWickTip;
   datetime          setupTime;
   datetime          lastArmTime;
   int               confluenceScore;  // 0–100
   string            reason;
   bool              entryFired;
};

struct SRiskParams {
   double riskPct;
   double maxDailyLossPct;
   double maxDailyProfitPct;
   int    maxTradesPerDay;
   double marginFloor;
};

struct SStreakControl {
   int    consecutiveLosses;
   int    consecutiveWins;
   double sizeMult;
};

struct STradeRecord {
   ulong    ticket;
   string   symbol;
   double   openPrice;
   double   stopLoss;
   double   takeProfit;
   double   lotSize;
   double   initialRisk;     // in price distance
   datetime openTime;
   bool     breakevenSet;
   bool     partial1Done;
   bool     partial2Done;
   ENUM_TRAIL_PHASE trailPhase;
};

//============================================================
//  IDENTITY
//============================================================
#define EA_NAME_V2         "InstEA_v2"
#define EA_VERSION_V2      "2.0.0"
#define MAGIC_NUMBER_V2    20260306L

//============================================================
//  PAIRS
//============================================================
#define PAIR_EURUSD   "EURUSD"
#define PAIR_GBPUSD   "GBPUSD"
#define PAIR_USDJPY   "USDJPY"
#define PAIR_USDCHF   "USDCHF"
#define PAIR_XAUUSD   "XAUUSD"
#define PAIR_BTCUSD   "BTCUSD"

//============================================================
//  SESSION WINDOWS (GMT hours)
//============================================================
#define ASIA_GMT_START       0
#define ASIA_GMT_END         6
#define LONDON_GMT_START     7
#define LONDON_GMT_END      10
#define NY_GMT_START        12
#define NY_GMT_END          15
#define OVERLAP_GMT_START   12
#define OVERLAP_GMT_END     14

//============================================================
//  SWEEP THRESHOLDS (pips)
//============================================================
#define SWEEP_MIN_FX         1.0
#define SWEEP_MAX_FX        18.0
#define SWEEP_MIN_JPY        0.5
#define SWEEP_MAX_JPY       15.0
#define SWEEP_MIN_GOLD       1.5
#define SWEEP_MAX_GOLD     120.0
#define SWEEP_MIN_BTC        5.0
#define SWEEP_MAX_BTC      800.0

//============================================================
//  SPREAD LIMITS
//============================================================
#define MAX_SPREAD_FX        2.5
#define MAX_SPREAD_GOLD      4.5
#define MAX_SPREAD_BTC      60.0

//============================================================
//  SL SIZING
//============================================================
#define MIN_SL_PIPS_FX       1.5
#define MAX_SL_PIPS_FX      14.0
#define MIN_SL_PIPS_JPY      1.5
#define MAX_SL_PIPS_JPY     14.0
#define MIN_SL_PIPS_GOLD     5.0
#define MAX_SL_PIPS_GOLD    90.0
#define MIN_SL_PIPS_BTC     30.0
#define MAX_SL_PIPS_BTC    600.0
#define SL_BUFFER_FX         1.0    // extra pips beyond sweep wick
#define SL_BUFFER_GOLD       2.0
#define SL_BUFFER_BTC       20.0

//============================================================
//  ASIA RANGE FILTER
//============================================================
#define MIN_ASIA_FX          3.0
#define MAX_ASIA_FX         45.0
#define MIN_ASIA_GOLD       15.0
#define MAX_ASIA_GOLD      180.0

//============================================================
//  SWING / STRUCTURE
//============================================================
#define SWING_LOOKBACK       4
#define MAX_SWING_POINTS    20
#define MIN_SWING_RANGE_FX   3.0
#define MIN_SWING_RANGE_GOLD 20.0

//============================================================
//  DISPLACEMENT
//============================================================
#define DISP_ATR_MULT        0.30   // min body size for displacement candle (M1 scalping)

//============================================================
//  TRADE MANAGEMENT R-LEVELS
//============================================================
#define BE_R_TRIGGER         0.5    // move SL to BE at 0.5R (scalping: protect fast)
#define PARTIAL1_R           1.0    // close 30% at 1R (lock profit on scalp)
#define PARTIAL2_R           2.0    // close 30% at 2R (let rest run)
#define PARTIAL1_PCT         0.30
#define PARTIAL2_PCT         0.30
#define TARGET_RR            2.0    // minimum RR to take trade (scalping = 2R minimum)

// Trailing SL phases (ATR multiplier behind price)
#define TRAIL_P1_START_R     0.5    // start tightening trail early on M1
#define TRAIL_P1_ATR_MULT    0.8    // tighter — M1 ATR is small
#define TRAIL_P2_START_R     1.0
#define TRAIL_P2_ATR_MULT    0.5
#define TRAIL_P3_START_R     2.0
#define TRAIL_P3_ATR_MULT    0.3    // very tight at 2R+ on scalp

//============================================================
//  RISK CONTROL
//============================================================
#define LOSSES_REDUCE_AT     2     // after 2 losses → 50% size
#define MARGIN_FLOOR        150.0  // % margin level floor
#define MAX_LOT_RISK_PCT     6.0   // 1:500 leverage — min lot acceptable up to 6% ($20 account)

//============================================================
//  CONFLUENCE SCORING THRESHOLDS
//============================================================
#define MIN_CONFLUENCE_SCORE 35    // out of 100 (SMC base is already 20)

//============================================================
//  EXECUTION
//============================================================
#define ENTRY_TOLERANCE_PTS   5   // fire market order if within 5 broker points
#define SETUP_MAX_AGE_BARS   25   // M1: 25 bars = ~25 min before setup expires
#define MIN_BARS_BETWEEN     3    // min M1 bars between trades on same pair (~3 min)

//============================================================
//  STREAK CONTROL
//============================================================
#define STREAK_REDUCE_LOSSES 2
#define STREAK_HALF_LOSSES   4

#endif // DEFINES_V2_MQH
