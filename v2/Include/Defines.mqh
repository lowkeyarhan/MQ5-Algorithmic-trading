//+------------------------------------------------------------------+
//|                                                    Defines.mqh   |
//|           Institutional EA v2.2 — Core Definitions               |
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
   TRAIL_PHASE1  = 1,   
   TRAIL_PHASE2  = 2,   
   TRAIL_PHASE3  = 3    
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
   double        displacementBody; 
};

struct SLiquidityPool {
   double   price;
   bool     isBuyStop;
   int      touchCount;
   int      ageInBars;
   double   score;        // 0–100
   datetime time;
   bool     active;
};

struct SOrderFlowData {
   double   cumulativeDelta;
   bool     absorptionDetected;
   bool     imbalanceDetected;
   bool     stopHuntBarDetected;
   bool     volumeDivergence;
   double   dominantDelta;
};

struct SMarketRegime {
   ENUM_REGIME      regime;
   ENUM_VOLATILITY  volatility;
   ENUM_HTF_BIAS    bias;       
   bool             biasStrong;
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
   int               confluenceScore;
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
   double   initialRisk;
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
#define EA_VERSION_V2      "2.2.0"
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
#define SL_BUFFER_FX         1.0    
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
#define DISP_ATR_MULT        0.30   

//============================================================
//  TRADE MANAGEMENT R-LEVELS
//============================================================
#define BE_R_TRIGGER         1.0    // Move SL to BE at 1.0R to protect capital
#define PARTIAL1_R           2.0    // First partial at 2R
#define PARTIAL2_R           3.0    // Second partial at 3R
#define PARTIAL1_PCT         0.20   // Secure margin
#define PARTIAL2_PCT         0.30   // Secure margin
#define TARGET_RR            4.0    // HARD CAP: Instant close at exactly 1:4 RR

// Trailing SL phases (ATR multiplier behind price)
#define TRAIL_P1_START_R     1.5    // Don't trail until 1.5R
#define TRAIL_P1_ATR_MULT    1.5    // Very loose trail initially
#define TRAIL_P2_START_R     2.5
#define TRAIL_P2_ATR_MULT    1.0
#define TRAIL_P3_START_R     3.5
#define TRAIL_P3_ATR_MULT    0.5    // Choke it only when deep in profit

//============================================================
//  RISK CONTROL
//============================================================
#define LOSSES_REDUCE_AT     2     
#define MARGIN_FLOOR        150.0  
#define MAX_LOT_RISK_PCT    10.0   // Raised to 10% to prevent micro-account rejection on 0.01 lots

//============================================================
//  CONFLUENCE SCORING THRESHOLDS
//============================================================
#define MIN_CONFLUENCE_SCORE 30    // Lowered slightly to accommodate immediate momentum entries

//============================================================
//  EXECUTION
//============================================================
#define ENTRY_TOLERANCE_PTS   5   
#define SETUP_MAX_AGE_BARS   25   
#define MIN_BARS_BETWEEN     3    

//============================================================
//  STREAK CONTROL
//============================================================
#define STREAK_REDUCE_LOSSES 2
#define STREAK_HALF_LOSSES   4

#endif // DEFINES_V2_MQH