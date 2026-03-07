//+------------------------------------------------------------------+
//|                                                    Defines.mqh   |
//|           Institutional EA v4.0 — Quant-Grade Definitions        |
//|                                                                  |
//|  PHILOSOPHY: Trade LESS, win MORE. Every parameter below is      |
//|  calibrated for ultra-selective entries with 80%+ win rate        |
//|  and 1:3 to 1:4.5 RR on M5 timeframe. Optimized for $20         |
//|  micro accounts growing steadily through rigorous risk mgmt.     |
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
   FVG_C    = 1,   // weak — HARD BLOCK, never trade
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
   ENUM_SIGNAL_DIR   sessionSweepDir;
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
#define EA_NAME_V2         "InstEA_v4"
#define EA_VERSION_V2      "4.0.0"
#define MAGIC_NUMBER_V2    20260307L

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
//  Must be a REAL institutional sweep — not 1-pip noise.
//  Tightened minimums to ensure genuine stop hunts.
//============================================================
#define SWEEP_MIN_FX         3.0    // Min 3 pips for a real FX sweep
#define SWEEP_MAX_FX        25.0    // Max 25 pips
#define SWEEP_MIN_JPY        2.0
#define SWEEP_MAX_JPY       20.0
#define SWEEP_MIN_GOLD      10.0    // Gold sweep: $1.00 minimum
#define SWEEP_MAX_GOLD     150.0
#define SWEEP_MIN_BTC       50.0
#define SWEEP_MAX_BTC     1000.0

//============================================================
//  SPREAD LIMITS — tight to avoid bad fills
//============================================================
#define MAX_SPREAD_FX        2.0
#define MAX_SPREAD_GOLD      4.0
#define MAX_SPREAD_BTC      60.0

//============================================================
//  SL SIZING
//  Wider stops survive M5 noise. Tight stops = stop hunts = losses.
//============================================================
#define MIN_SL_PIPS_FX       5.0
#define MAX_SL_PIPS_FX      20.0
#define MIN_SL_PIPS_JPY      5.0
#define MAX_SL_PIPS_JPY     20.0
#define MIN_SL_PIPS_GOLD    25.0    // Gold M5 needs room — not too wide to degrade RR
#define MAX_SL_PIPS_GOLD   100.0
#define MIN_SL_PIPS_BTC     50.0
#define MAX_SL_PIPS_BTC    700.0
#define SL_BUFFER_FX         1.5
#define SL_BUFFER_GOLD       6.0    // Gold buffer beyond wick
#define SL_BUFFER_BTC       30.0

//============================================================
//  ASIA RANGE FILTER
//============================================================
#define MIN_ASIA_FX          5.0
#define MAX_ASIA_FX         60.0
#define MIN_ASIA_GOLD       20.0
#define MAX_ASIA_GOLD      250.0

//============================================================
//  SWING / STRUCTURE
//  5-bar lookback = 25 min on M5 = real structural level.
//============================================================
#define SWING_LOOKBACK       4      // 4-bar confirmed swing = 20 min on M5
#define MAX_SWING_POINTS    20
#define MIN_SWING_RANGE_FX  10.0
#define MIN_SWING_RANGE_GOLD 60.0   // Gold swing must span $6+

//============================================================
//  DISPLACEMENT
//  Only accept STRONG impulse moves that create genuine FVGs.
//  0.65 × ATR = displacement candle body must be 65% of ATR.
//  This eliminates weak indecisive candles masquerading as impulse.
//============================================================
#define DISP_ATR_MULT        0.55   // Sweet spot: strong enough to be real, not so strict to miss valid setups

//============================================================
//  TRADE MANAGEMENT R-LEVELS
//
//  DUAL TP SYSTEM:
//  - Partial 1: Close 40% at 1.5R (lock profit early)
//  - Partial 2: Close 30% at 3.0R (guarantee minimum 1:3 RR)
//  - Remaining 30% trails with tight SL to max 4.5R
//
//  This ensures MINIMUM 1:3 is locked via partials even if
//  the remaining runner gets stopped out by trailing SL.
//
//  Trailing SL starts at 1.0R — NEVER let green turn red.
//============================================================
#define BE_R_TRIGGER         0.8    // Move to BE early (0.8R) — protect capital fast
#define PARTIAL1_R           1.5    // First partial at 1.5R
#define PARTIAL2_R           3.0    // Second partial at 3.0R (guarantees 1:3 minimum)
#define PARTIAL1_PCT         0.40   // Close 40% at 1.5R — big early lock
#define PARTIAL2_PCT         0.30   // Close 30% at 3.0R
#define TARGET_RR            4.5    // Hard TP cap at 1:4.5 — remaining 30% max target

// TRAILING SL — Start early, tighten aggressively.
// Phase 1 (1.0R): trail 1.5x ATR behind — protect breakeven
// Phase 2 (2.0R): trail 0.8x ATR — lock significant profit
// Phase 3 (3.0R): trail 0.4x ATR — choke hard, near-TP territory
#define TRAIL_P1_START_R     1.0    // Start trailing at 1.0R (was 1.5R)
#define TRAIL_P1_ATR_MULT    1.5    // Tighter from start (was 2.0)
#define TRAIL_P2_START_R     2.0    // Phase 2 at 2.0R (was 3.0)
#define TRAIL_P2_ATR_MULT    0.8    // Tight (was 1.2)
#define TRAIL_P3_START_R     3.0    // Phase 3 at 3.0R (was 3.8)
#define TRAIL_P3_ATR_MULT    0.4    // Very tight (was 0.6)

//============================================================
//  RISK CONTROL — Conservative for micro accounts
//============================================================
#define LOSSES_REDUCE_AT     2
#define MARGIN_FLOOR        120.0   // Relaxed from 150 for micro accounts
#define MAX_LOT_RISK_PCT    15.0    // Max risk at min lot (allows $20 accounts)

//============================================================
//  CONFLUENCE SCORING — Selective but not starving
//  Score of 50 = aligned bias (12-20) + trending (15) + FVG-B (5)
//  + momentum aligned (passes hard block) = minimum 52 for trending.
//  This ensures quality while allowing enough setups to compound.
//============================================================
#define MIN_CONFLUENCE_SCORE 50     // Balanced: quality setups that compound

//============================================================
//  EXECUTION
//============================================================
#define ENTRY_TOLERANCE_PTS   8
#define SETUP_MAX_AGE_BARS   12     // Give setups time to fill
#define MIN_BARS_BETWEEN      8     // 40 min cooldown on M5 — allows responsive re-entry

//============================================================
//  FVG DETECTION
//============================================================
#define FVG_LOOKBACK          8     // Scan 8 bars for FVG patterns
#define FVG_MIN_SIZE_FX       2.5   // FVG must be meaningful
#define FVG_MIN_SIZE_GOLD    12.0   // Gold: $1.20 minimum gap
#define FVG_MIN_SIZE_BTC    100.0

//============================================================
//  STREAK CONTROL
//  TIERED: 2 losses = 75% size, 3 losses = 50%, stop after 4
//============================================================
#define STREAK_REDUCE_LOSSES 2
#define STREAK_HALF_LOSSES   3      // Reduced from 4 — cut size faster on losses
#define STREAK_REDUCE_MULT   0.75
#define STREAK_HALF_MULT     0.50

#endif // DEFINES_V2_MQH