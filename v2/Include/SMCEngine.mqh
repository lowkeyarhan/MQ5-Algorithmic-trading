//+------------------------------------------------------------------+
//|                                                  SMCEngine.mqh   |
//|      Institutional EA v2.2 — Advanced Smart Money Concepts       |
//+------------------------------------------------------------------+
#ifndef SMCENGINE_V2_MQH
#define SMCENGINE_V2_MQH

#include "Defines.mqh"

class CSMCEngine {
private:
   string           m_symbol;
   ENUM_TIMEFRAMES  m_tf;       
   ENUM_TIMEFRAMES  m_htf;
   bool             m_isGold;
   bool             m_isJPY;
   bool             m_isBTC;
   double           m_pipSize;

   SAsiaLevels      m_asia;
   SConfluenceSetup m_setup;
   datetime         m_lastTradeBar;
   datetime         m_lastSwingUpdate;

   SSwingPoint      m_swingHighs[MAX_SWING_POINTS];
   SSwingPoint      m_swingLows[MAX_SWING_POINTS];
   int              m_shCount;
   int              m_slCount;

   // Session sweep direction: direction of the FIRST confirmed sweep this session.
   // Used to identify trend-continuation setups and award scoring bonuses.
   ENUM_SIGNAL_DIR  m_sessionSweepDir;

   double PipsToPrice(double pips) { return pips * m_pipSize; }
   double PriceToPips(double d)    { return (m_pipSize > 0) ? d / m_pipSize : 0; }

   double GetATR(ENUM_TIMEFRAMES tf, int period = 14) {
      double buf[];
      ArraySetAsSeries(buf, true);
      int h = iATR(m_symbol, tf, period);
      if(h == INVALID_HANDLE) return 0;
      int c = CopyBuffer(h, 0, 1, period + 2, buf);
      IndicatorRelease(h);
      return (c >= 1) ? buf[0] : 0;
   }

   //==========================================================
   // REAL 3-CANDLE FVG DETECTION
   // Bullish FVG: iHigh(i+2) < iLow(i) with strong bullish displacement at i+1
   // Bearish FVG: iLow(i+2)  > iHigh(i) with strong bearish displacement at i+1
   //
   // Requirements tightened for quality:
   //  - Displacement body >= DISP_ATR_MULT (0.65) × ATR
   //  - FVG gap itself >= FVG_MIN_SIZE (not a micro-gap)
   //  - Grade A: body >= 0.75 ATR (strongest impulse)
   //  - Grade B: body >= 0.55 ATR (still acceptable)
   //  - Grade C: anything weaker → HARD BLOCK, never trade
   //==========================================================
   bool FindFVG(ENUM_SIGNAL_DIR dir, SFVG &fvg) {
      double atr = GetATR(m_tf, 14);
      if(atr <= 0) return false;
      double minDisp    = atr * DISP_ATR_MULT;
      double minFvgSize = PipsToPrice(m_isGold ? FVG_MIN_SIZE_GOLD :
                                     (m_isBTC  ? FVG_MIN_SIZE_BTC  : FVG_MIN_SIZE_FX));

      int avail = iBars(m_symbol, m_tf);
      int scan  = MathMin(FVG_LOOKBACK, avail - 4);

      for(int i = 1; i <= scan; i++) {
         double hi0 = iHigh(m_symbol, m_tf, i);
         double lo0 = iLow(m_symbol,  m_tf, i);
         double cl1 = iClose(m_symbol, m_tf, i + 1);
         double op1 = iOpen(m_symbol,  m_tf, i + 1);
         double hi2 = iHigh(m_symbol, m_tf, i + 2);
         double lo2 = iLow(m_symbol,  m_tf, i + 2);

         if(dir == DIR_BUY) {
            double dispBody = cl1 - op1;
            if(hi2 >= lo0)             continue; // no gap
            if(dispBody <= 0)          continue; // must be bullish
            if(dispBody < minDisp)     continue; // too weak
            double gapSize = lo0 - hi2;
            if(gapSize < minFvgSize)   continue; // FVG too small = noise

            fvg.upper  = lo0;
            fvg.lower  = hi2;
            // Enter at the lower 40% of the FVG — better price, wider cushion above
            fvg.midpoint         = hi2 + gapSize * 0.40;
            fvg.isBullish        = true;
            fvg.time             = iTime(m_symbol, m_tf, i + 2);
            fvg.active           = true;
            fvg.touchCount       = 0;
            fvg.displacementBody = dispBody;

            if(dispBody >= atr * 0.75)      fvg.grade = FVG_A;
            else if(dispBody >= atr * 0.55) fvg.grade = FVG_B;
            else                            fvg.grade = FVG_C;
            return true;

         } else { // DIR_SELL
            double dispBody = op1 - cl1;
            if(lo2 <= hi0)             continue; // no gap
            if(dispBody <= 0)          continue; // must be bearish
            if(dispBody < minDisp)     continue; // too weak
            double gapSize = lo2 - hi0;
            if(gapSize < minFvgSize)   continue; // FVG too small

            fvg.upper  = lo2;
            fvg.lower  = hi0;
            // Enter at the upper 60% of the FVG — better price for sells
            fvg.midpoint         = hi0 + gapSize * 0.60;
            fvg.isBullish        = false;
            fvg.time             = iTime(m_symbol, m_tf, i + 2);
            fvg.active           = true;
            fvg.touchCount       = 0;
            fvg.displacementBody = dispBody;

            if(dispBody >= atr * 0.75)      fvg.grade = FVG_A;
            else if(dispBody >= atr * 0.55) fvg.grade = FVG_B;
            else                            fvg.grade = FVG_C;
            return true;
         }
      }
      return false;
   }

   int DetectGMTOffset() {
      return (int)(TimeCurrent() - TimeGMT());
   }

   void ServerTimeGMT(datetime t, int &h, int &m) {
      int offSec = DetectGMTOffset();
      datetime gmt = t - offSec;
      MqlDateTime dt; TimeToStruct(gmt, dt);
      h = dt.hour; m = dt.min;
   }

   datetime GetGMTDate() {
      MqlDateTime dt; TimeToStruct(TimeGMT(), dt);
      dt.hour = 0;
      dt.min = 0; dt.sec = 0;
      return StructToTime(dt);
   }

   bool SpreadOK() {
      double sp = (double)SymbolInfoInteger(m_symbol, SYMBOL_SPREAD) *
                  SymbolInfoDouble(m_symbol, SYMBOL_POINT);
      double spPips = PriceToPips(sp);
      double maxP   = m_isGold ? MAX_SPREAD_GOLD : (m_isBTC ? MAX_SPREAD_BTC : MAX_SPREAD_FX);
      return (spPips <= maxP);
   }

   void MapAsiaLevels() {
      datetime today = GetGMTDate();
      if(m_asia.valid && m_asia.date == today) return;

      m_asia.high = -1; m_asia.low = DBL_MAX;
      m_asia.valid = false; m_asia.highSwept = false;
      m_asia.lowSwept = false;
      m_asia.date  = today;

      int bars = iBars(m_symbol, m_tf);
      int scan = MathMin(bars - 1, 600);
      int cnt  = 0;

      for(int i = 1; i <= scan; i++) {
         datetime bt = iTime(m_symbol, m_tf, i);
         if(bt <= 0) continue;
         int gh, gm; ServerTimeGMT(bt, gh, gm);
         MqlDateTime bmdt; TimeToStruct(bt - DetectGMTOffset(), bmdt);
         bmdt.hour = 0;
         bmdt.min = 0; bmdt.sec = 0;
         if(StructToTime(bmdt) != today) { if(cnt > 0) break; continue; }

         if(gh >= ASIA_GMT_START && gh < ASIA_GMT_END) {
            double h = iHigh(m_symbol, m_tf, i);
            double l = iLow(m_symbol,  m_tf, i);
            if(h > m_asia.high) { m_asia.high = h; m_asia.highTime = bt; }
            if(l < m_asia.low)  { m_asia.low  = l; m_asia.lowTime  = bt; }
            cnt++;
         }
      }

      if(cnt >= 4 && m_asia.high > 0 && m_asia.low < DBL_MAX && m_asia.high > m_asia.low) {
         double range = PriceToPips(m_asia.high - m_asia.low);
         double minR  = m_isGold ? MIN_ASIA_GOLD : MIN_ASIA_FX;
         double maxR  = m_isGold ? MAX_ASIA_GOLD : MAX_ASIA_FX;
         if(range >= minR && range <= maxR) {
            m_asia.valid = true;
            Print("[", m_symbol, "] Asia mapped H=", DoubleToString(m_asia.high, 4),
                  " L=", DoubleToString(m_asia.low, 4),
                  " range=", DoubleToString(range, 1), "p");
         }
      }
   }

   void UpdateSwings() {
      datetime cur = iTime(m_symbol, m_tf, 0);
      if(cur == m_lastSwingUpdate) return;
      m_lastSwingUpdate = cur;

      m_shCount = 0; m_slCount = 0;
      int lb    = SWING_LOOKBACK;
      int bars  = iBars(m_symbol, m_tf);
      int scan  = MathMin(bars - lb - 1, 200);
      
      double minRange = PipsToPrice(m_isGold ? MIN_SWING_RANGE_GOLD : MIN_SWING_RANGE_FX);
      for(int i = lb; i < scan - lb && (m_shCount < MAX_SWING_POINTS && m_slCount < MAX_SWING_POINTS); i++) {
         double hi = iHigh(m_symbol, m_tf, i);
         double lo = iLow(m_symbol,  m_tf, i);

         if(m_shCount < MAX_SWING_POINTS) {
            bool sw = true;
            for(int j = 1; j <= lb && sw; j++)
               if(iHigh(m_symbol, m_tf, i-j) >= hi || iHigh(m_symbol, m_tf, i+j) >= hi)
                  sw = false;
            if(sw) {
               double lLow = lo;
               for(int j = 1; j <= lb; j++) { double l2 = iLow(m_symbol, m_tf, i+j); if(l2 < lLow) lLow = l2; }
               if(hi - lLow >= minRange) {
                  m_swingHighs[m_shCount].price    = hi;
                  m_swingHighs[m_shCount].time     = iTime(m_symbol, m_tf, i);
                  m_swingHighs[m_shCount].barIndex = i;
                  m_swingHighs[m_shCount].isHigh   = true;
                  m_swingHighs[m_shCount].swept    = false;
                  m_swingHighs[m_shCount].touchCount = 1;
                  m_shCount++;
               }
            }
         }

         if(m_slCount < MAX_SWING_POINTS) {
            bool sw = true;
            for(int j = 1; j <= lb && sw; j++)
               if(iLow(m_symbol, m_tf, i-j) <= lo || iLow(m_symbol, m_tf, i+j) <= lo)
                  sw = false;
            if(sw) {
               double lHigh = hi;
               for(int j = 1; j <= lb; j++) { double h2 = iHigh(m_symbol, m_tf, i+j); if(h2 > lHigh) lHigh = h2; }
               if(lHigh - lo >= minRange) {
                  m_swingLows[m_slCount].price    = lo;
                  m_swingLows[m_slCount].time     = iTime(m_symbol, m_tf, i);
                  m_swingLows[m_slCount].barIndex = i;
                  m_swingLows[m_slCount].isHigh   = false;
                  m_swingLows[m_slCount].swept    = false;
                  m_swingLows[m_slCount].touchCount = 1;
                  m_slCount++;
               }
            }
         }
      }
   }

   bool CheckAsiaSweep(ENUM_SIGNAL_DIR &dir, double &wickTip, datetime &sweepTime) {
      if(!m_asia.valid) return false;
      double swMin = PipsToPrice(m_isGold ? SWEEP_MIN_GOLD : (m_isBTC ? SWEEP_MIN_BTC : SWEEP_MIN_FX));
      double swMax = PipsToPrice(m_isGold ? SWEEP_MAX_GOLD : (m_isBTC ? SWEEP_MAX_BTC : SWEEP_MAX_FX));
      for(int i = 1; i <= 5; i++) {  // Scan 5 recent bars for Asia sweep
         double hi = iHigh(m_symbol, m_tf, i);
         double lo = iLow(m_symbol,  m_tf, i);
         double cl = iClose(m_symbol,m_tf, i);
         if(!m_asia.highSwept) {
            double p = hi - m_asia.high;
            if(p >= swMin && p <= swMax && cl <= m_asia.high) {
               m_asia.highSwept = true;
               dir = DIR_SELL; wickTip = hi;
               sweepTime = iTime(m_symbol, m_tf, i);
               return true;
            }
         }
         if(!m_asia.lowSwept) {
            double p = m_asia.low - lo;
            if(p >= swMin && p <= swMax && cl >= m_asia.low) {
               m_asia.lowSwept = true;
               dir = DIR_BUY; wickTip = lo;
               sweepTime = iTime(m_symbol, m_tf, i);
               return true;
            }
         }
      }
      return false;
   }

   bool CheckSwingSweep(ENUM_SIGNAL_DIR &dir, double &wickTip, datetime &sweepTime) {
      double swMin = PipsToPrice(m_isGold ? SWEEP_MIN_GOLD : (m_isBTC ? SWEEP_MIN_BTC : SWEEP_MIN_FX));
      double swMax = PipsToPrice(m_isGold ? SWEEP_MAX_GOLD : (m_isBTC ? SWEEP_MAX_BTC : SWEEP_MAX_FX));
      // TIGHTENED: swing must be at least SWING_LOOKBACK×4 bars old.
      // On M5: 6×4 = 24 bars = 2 hours minimum. This ensures we're sweeping a
      // real structural level, not a 20-minute micro-swing.
      int minAge   = SWING_LOOKBACK * 4;
      for(int i = 1; i <= 8; i++) { 
         double hi = iHigh(m_symbol, m_tf, i);
         double lo = iLow(m_symbol,  m_tf, i);
         double cl = iClose(m_symbol,m_tf, i);
         for(int s = 0; s < m_shCount; s++) {
            if(m_swingHighs[s].swept) continue;
            if(m_swingHighs[s].barIndex - i < minAge) continue;
            double p = hi - m_swingHighs[s].price;
            if(p >= swMin && p <= swMax && cl <= m_swingHighs[s].price) {
               m_swingHighs[s].swept = true;
               dir = DIR_SELL; wickTip = hi;
               sweepTime = iTime(m_symbol, m_tf, i);
               return true;
            }
         }
         for(int s = 0; s < m_slCount; s++) {
            if(m_swingLows[s].swept) continue;
            if(m_swingLows[s].barIndex - i < minAge) continue;
            double p = m_swingLows[s].price - lo;
            if(p >= swMin && p <= swMax && cl >= m_swingLows[s].price) {
               m_swingLows[s].swept = true;
               dir = DIR_BUY; wickTip = lo;
               sweepTime = iTime(m_symbol, m_tf, i);
               return true;
            }
         }
      }
      return false;
   }

   //==========================================================
   // BUILD SETUP FROM FVG - HARD CAP TP
   //==========================================================
   bool BuildSetup(ENUM_SIGNAL_DIR dir, SFVG &fvg, double wickTip, ENUM_SESSION ses) {
      int digits = (int)SymbolInfoInteger(m_symbol, SYMBOL_DIGITS);
      double entry  = NormalizeDouble(fvg.midpoint, digits);
      double buffer = PipsToPrice(m_isGold ? SL_BUFFER_GOLD : (m_isBTC ? SL_BUFFER_BTC : SL_BUFFER_FX));

      double sl;
      if(dir == DIR_BUY)  sl = NormalizeDouble(wickTip - buffer, digits);
      else                sl = NormalizeDouble(wickTip + buffer, digits);
      if(dir == DIR_BUY  && entry <= sl) return false;
      if(dir == DIR_SELL && entry >= sl) return false;
      
      double slDist = MathAbs(entry - sl);
      double slPips = PriceToPips(slDist);

      double minSL = m_isGold ? MIN_SL_PIPS_GOLD : (m_isBTC ? MIN_SL_PIPS_BTC : (m_isJPY ? MIN_SL_PIPS_JPY : MIN_SL_PIPS_FX));
      double maxSL = m_isGold ? MAX_SL_PIPS_GOLD : (m_isBTC ? MAX_SL_PIPS_BTC : (m_isJPY ? MAX_SL_PIPS_JPY : MAX_SL_PIPS_FX));
      if(slPips < minSL || slPips > maxSL) {
         return false;
      }

      // --- HARD CAP TAKE PROFIT LOGIC ---
      double tpDist = slDist * TARGET_RR;
      double tp;
      if(dir == DIR_BUY)
         tp = NormalizeDouble(entry + tpDist, digits);
      else
         tp = NormalizeDouble(entry - tpDist, digits);
         
      double rr = MathAbs(tp - entry) / slDist;

      m_setup.direction       = dir;
      m_setup.entryPrice      = entry;
      m_setup.stopLoss        = sl;
      m_setup.takeProfit      = tp;
      m_setup.riskReward      = rr;
      m_setup.slPips          = slPips;
      m_setup.fvg             = fvg;
      m_setup.sweepWickTip    = wickTip;
      m_setup.session         = ses;
      m_setup.setupTime       = TimeCurrent();
      m_setup.lastArmTime     = 0;
      m_setup.phase           = PHASE_CONFIRMED;
      m_setup.entryFired      = false;
      m_setup.confluenceScore = 0;
      // Snapshot the established session direction BEFORE we update it.
      // DIR_NONE = this is the first trade of the session (no continuation bonus).
      // Any other value = prior sweep established the session direction (eligible for +10 bonus).
      m_setup.sessionSweepDir = m_sessionSweepDir;
      m_setup.reason          = StringFormat("%s %s SL=%.1fp RR=1:%.1f",
                                (dir == DIR_BUY ? "BUY" : "SELL"), m_symbol, slPips, rr);
      Print("[", m_symbol, "] SETUP BUILT: ", m_setup.reason);
      return true;
   }

public:
   CSMCEngine(string symbol, ENUM_TIMEFRAMES tf, ENUM_TIMEFRAMES htf) {
      m_symbol = symbol;
      m_tf = tf; m_htf = htf;
      m_isGold = (StringFind(symbol, "XAU") >= 0 || StringFind(symbol, "GOLD") >= 0);
      m_isJPY  = (StringFind(symbol, "JPY") >= 0);
      m_isBTC  = (StringFind(symbol, "BTC") >= 0);
      if(m_isGold)      m_pipSize = 0.10;
      else if(m_isJPY)  m_pipSize = 0.01;
      else if(m_isBTC)  m_pipSize = 1.0;
      else              m_pipSize = 0.0001;
      ZeroMemory(m_asia); ZeroMemory(m_setup);
      m_setup.phase = PHASE_IDLE;
      m_shCount = 0; m_slCount = 0;
      m_lastTradeBar = 0; m_lastSwingUpdate = 0;
      m_sessionSweepDir = DIR_NONE;
   }

   bool Update(ENUM_SESSION session) {
      if(m_setup.phase == PHASE_CONFIRMED) return true;

      // Always update swings and map Asia levels — regardless of session
      UpdateSwings();
      if(session == SESSION_ASIA) MapAsiaLevels();

      // FIXED: Only seek entries during active Kill Zone sessions.
      // SESSION_OTHER (dead zones 10-12 GMT, 15+ GMT) is explicitly excluded.
      bool activeSession = (session == SESSION_LONDON    ||
                            session == SESSION_NY        ||
                            session == SESSION_LONDON_NY);
      if(!activeSession) return false;

      datetime curBar = iTime(m_symbol, m_tf, 0);
      if(m_lastTradeBar > 0) {
         int barsSince = (int)((curBar - m_lastTradeBar) / PeriodSeconds(m_tf));
         if(barsSince < MIN_BARS_BETWEEN) return false;
      }

      if(!SpreadOK()) return false;
      if(!m_asia.valid) MapAsiaLevels(); // fallback map if EA started mid-day

      // Cut off new setups late in NY (avoid holding through session close)
      MqlDateTime dt; TimeToStruct(TimeGMT(), dt);
      if(dt.hour == 14 && dt.min >= 45) return false;

      ENUM_SIGNAL_DIR sweepDir = DIR_NONE;
      double wickTip   = 0;
      datetime sweepTime = 0;

      bool swept = CheckAsiaSweep(sweepDir, wickTip, sweepTime);
      if(!swept) swept = CheckSwingSweep(sweepDir, wickTip, sweepTime);
      if(!swept) return false;

      // Require a real 3-candle FVG. No fallback, no momentum-only entries.
      SFVG fvg;
      ZeroMemory(fvg);
      if(!FindFVG(sweepDir, fvg)) return false;

      // C-grade FVGs are noise — HARD BLOCK.
      if(fvg.grade == FVG_C) return false;

      bool built = BuildSetup(sweepDir, fvg, wickTip, session);
      if(built) {
         if(m_sessionSweepDir == DIR_NONE)
            m_sessionSweepDir = sweepDir;
      }
      return built;
   }

   void ResetDay() {
      ZeroMemory(m_asia);
      if(m_setup.phase != PHASE_IN_TRADE)
         m_setup.phase = PHASE_IDLE;
      m_sessionSweepDir = DIR_NONE; // New day = fresh session direction
   }

   void ResetSession() {
      if(m_setup.phase != PHASE_CONFIRMED && m_setup.phase != PHASE_IN_TRADE)
         m_setup.phase = PHASE_IDLE;
      // Reset session direction so each kill zone builds its own trend context.
      // London and NY can move in different directions — don't carry over.
      m_sessionSweepDir = DIR_NONE;
   }

   void OnTradePlaced() {
      m_lastTradeBar = iTime(m_symbol, m_tf, 0);
      m_setup.phase  = PHASE_IN_TRADE;
   }

   void OnTradeClose() {
      m_setup.phase     = PHASE_DONE;
      m_setup.entryFired = false;
   }

   void InvalidateSetup() {
      ZeroMemory(m_setup);
      m_setup.phase = PHASE_IDLE;
   }

   SConfluenceSetup  GetSetup()      { return m_setup; }
   SAsiaLevels       GetAsiaLevels() { return m_asia;  }
   bool              HasSetup()      { return (m_setup.phase == PHASE_CONFIRMED); }
   ENUM_SETUP_PHASE  GetPhase()      { return m_setup.phase; }

   void SetScore(int score) { m_setup.confluenceScore = score; }
};

#endif // SMCENGINE_V2_MQH