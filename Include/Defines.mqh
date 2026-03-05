//+------------------------------------------------------------------+
//|                                                      Defines.mqh |
//|           SMC Structure + Liquidity Sweep Scalper                |
//|                     Core Definitions v4.0                        |
//+------------------------------------------------------------------+
#ifndef DEFINES_MQH
#define DEFINES_MQH

enum ENUM_SIGNAL_DIRECTION {
    SIGNAL_NONE = 0,
    SIGNAL_BUY = 1,
    SIGNAL_SELL = - 1
};

enum ENUM_EA_STATE {
    STATE_NORMAL = 0,
    STATE_REDUCED = 1,
    STATE_PAUSED = 2,
    STATE_RECOVERY = 3
};

enum ENUM_SESSION {
    SESSION_NONE = 0,
    SESSION_ASIA = 1,
    SESSION_LONDON_KILL = 2,
    SESSION_NY_KILL = 3,
    SESSION_OTHER = 4
};

enum ENUM_SETUP_PHASE {
    PHASE_IDLE = 0,
    PHASE_WATCHING = 1,
    PHASE_SWEPT = 2,
    PHASE_CONFIRMED = 3,
    PHASE_IN_TRADE = 4,
    PHASE_DONE = 5
};

enum ENUM_HTF_BIAS {
    BIAS_NONE = 0,
    BIAS_BULLISH = 1,
    BIAS_BEARISH = 2
};

struct SAsiaLevels {
    double high;
    double low;
    datetime highTime;
    datetime lowTime;
    bool valid;
    bool highSwept;
    bool lowSwept;
    double sweepWickTip;
    datetime sweepTime;
    datetime date;
};

struct SFVG {
    double upper;
    double lower;
    double midpoint;
    bool isBullish;
    datetime time;
    bool active;
};

struct SSetup {
    ENUM_SIGNAL_DIRECTION direction;
    ENUM_SETUP_PHASE phase;
    ENUM_SESSION session;
    double entryPrice;
    double stopLoss;
    double takeProfit;
    double riskReward;
    double slPips;
    bool chochDone;
    bool fvgFound;
    SFVG fvg;
    datetime setupTime;
    string reason;
};

struct STradeRecord {
    ulong ticket;
    string symbol;
    double openPrice;
    double stopLoss;
    double takeProfit;
    double lotSize;
    datetime openTime;
    bool breakevenSet;
    bool partialClosed;
    double initialRisk;
};

struct SRiskParams {
    double riskPct;
    double maxDailyLossPct;
    double maxDailyProfitPct;
    double maxDrawdownPct;
    int maxTradesPerDay;
    double minRR;
    double marginFloor;
};

struct SStreakControl {
    int consecutiveLosses;
    int consecutiveWins;
    datetime pauseUntil;
    int recoveryWins;
    double sizeMult;
};

//============================================================
//  CONSTANTS
//============================================================
#define EA_NAME            "SMC_ScalperEA"
#define EA_VERSION         "4.0.0"
#define MAGIC_NUMBER       20250305L

// Killzones (GMT hours) -- widened for reliability
#define LONDON_KILL_H_START  7
#define LONDON_KILL_H_END    10
#define NY_KILL_H_START      12
#define NY_KILL_H_END        15

// Asia session window (GMT)
#define ASIA_H_START   0
#define ASIA_H_END     7

// Sweep: pierce must be at least this many pips beyond Asia level
#define SWEEP_MIN_PIPS_FX    0.5
#define SWEEP_MIN_PIPS_JPY   0.3
#define SWEEP_MIN_PIPS_GOLD  0.5
#define SWEEP_MAX_PIPS_FX   25.0
#define SWEEP_MAX_PIPS_JPY  25.0
#define SWEEP_MAX_PIPS_GOLD 300.0

// Displacement candle body must be >= this fraction of ATR
#define DISP_ATR_MULT    0.5

// Locked minimum 1:3 R:R
#define TARGET_RR        3.0

// Max SL in pips -- reject wider setups
#define MAX_SL_PIPS_FOREX  15.0
#define MAX_SL_PIPS_JPY    15.0
#define MAX_SL_PIPS_GOLD   200.0
#define MAX_SL_PIPS_BTC    500.0

// Streak thresholds
#define LOSSES_REDUCE    2
#define LOSSES_PAUSE     4
#define RECOVERY_WINS    3
#define PAUSE_HOURS      4

// Margin floor
#define MARGIN_KILL      150.0

// Max spread to allow entry (pips)
#define MAX_SPREAD_PIPS_FX   3.0
#define MAX_SPREAD_PIPS_GOLD 5.0
#define MAX_SPREAD_PIPS_BTC  50.0

// How many M5 bars after sweep to look for CHoCH+FVG before giving up
#define MAX_BARS_AFTER_SWEEP 12

// Pairs
#define PAIR_EURUSD  "EURUSD"
#define PAIR_GBPUSD  "GBPUSD"
#define PAIR_USDJPY  "USDJPY"
#define PAIR_XAUUSD  "XAUUSD"
#define PAIR_BTCUSD  "BTCUSD"

#endif
