//+------------------------------------------------------------------+
//|                                                  SMCEngine.mqh   |
//|      Institutional EA v2 — Advanced Smart Money Concepts         |
//|  2-TF validated CHoCH/BOS. Quality-graded FVG. OB mitigation.  |
//|  Asia level mapping. Swing pool tracking. Scored setups.        |
//+------------------------------------------------------------------+
#ifndef SMCENGINE_V2_MQH
#define SMCENGINE_V2_MQH

#include "Defines.mqh"

class CSMCEngine {
private:
   string           m_symbol;
   ENUM_TIMEFRAMES  m_tf;       // entry TF (M5)
   ENUM_TIMEFRAMES  m_htf;      // confirmation TF (M15)
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

   //-----------------------------------------------------------
   double PipsToPrice(double pips) { return pips * m_pipSize; }
   double PriceToPips(double d)    { return (m_pipSize > 0) ? d / m_pipSize : 0; }

   double GetATR(ENUM_TIMEFRAMES tf, int period = 14) {
      double buf[];
      ArraySetAsSeries(buf, true);
      int h = iATR(m_symbol, tf, period);
      if(h == INVALID_HANDLE) return 0;
      int c = CopyBuffer(h, 0, 1, 3, buf);
      IndicatorRelease(h);
      return (c >= 1) ? buf[0] : 0;
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
      dt.hour = 0; dt.min = 0; dt.sec = 0;
      return StructToTime(dt);
   }

   bool SpreadOK() {
      double sp = (double)SymbolInfoInteger(m_symbol, SYMBOL_SPREAD) *
                  SymbolInfoDouble(m_symbol, SYMBOL_POINT);
      double spPips = PriceToPips(sp);
      double maxP   = m_isGold ? MAX_SPREAD_GOLD : (m_isBTC ? MAX_SPREAD_BTC : MAX_SPREAD_FX);
      return (spPips <= maxP);
   }

   //==========================================================
   // ASIA LEVEL MAPPING
   //==========================================================
   void MapAsiaLevels() {
      datetime today = GetGMTDate();
      if(m_asia.valid && m_asia.date == today) return;

      m_asia.high = -1; m_asia.low = DBL_MAX;
      m_asia.valid = false; m_asia.highSwept = false; m_asia.lowSwept = false;
      m_asia.date  = today;

      int bars = iBars(m_symbol, m_tf);
      int scan = MathMin(bars - 1, 600);
      int cnt  = 0;

      for(int i = 1; i <= scan; i++) {
         datetime bt = iTime(m_symbol, m_tf, i);
         if(bt <= 0) continue;
         int gh, gm; ServerTimeGMT(bt, gh, gm);
         MqlDateTime bmdt; TimeToStruct(bt - DetectGMTOffset(), bmdt);
         bmdt.hour = 0; bmdt.min = 0; bmdt.sec = 0;
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

   //==========================================================
   // SWING STRUCTURE (M5)
   //==========================================================
   void UpdateSwings() {
      datetime cur = iTime(m_symbol, m_tf, 0);
      if(cur == m_lastSwingUpdate) return;
      m_lastSwingUpdate = cur;

      m_shCount = 0; m_slCount = 0;
      int lb    = SWING_LOOKBACK;
      int bars  = iBars(m_symbol, m_tf);
      int scan  = MathMin(bars - lb - 1, 200); // scan more bars on M1
      double minRange = PipsToPrice(m_isGold ? MIN_SWING_RANGE_GOLD : MIN_SWING_RANGE_FX);

      for(int i = lb; i < scan - lb && (m_shCount < MAX_SWING_POINTS && m_slCount < MAX_SWING_POINTS); i++) {
         double hi = iHigh(m_symbol, m_tf, i);
         double lo = iLow(m_symbol,  m_tf, i);

         // Swing High
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

         // Swing Low
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

   //==========================================================
   // SWEEP DETECTION
   //==========================================================
   bool CheckAsiaSweep(ENUM_SIGNAL_DIR &dir, double &wickTip, datetime &sweepTime) {
      if(!m_asia.valid) return false;
      double swMin = PipsToPrice(m_isGold ? SWEEP_MIN_GOLD : (m_isBTC ? SWEEP_MIN_BTC : SWEEP_MIN_FX));
      double swMax = PipsToPrice(m_isGold ? SWEEP_MAX_GOLD : (m_isBTC ? SWEEP_MAX_BTC : SWEEP_MAX_FX));

      for(int i = 1; i <= 5; i++) {
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
      int minAge   = SWING_LOOKBACK * 2;

      for(int i = 1; i <= 8; i++) {  // scan more bars for sweep on M1
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
   // STRUCTURE LEVEL FOR CHoCH (fractal-based)
   //==========================================================
   bool FindStructureLevel(ENUM_SIGNAL_DIR dir, datetime sweepTime, double &level) {
      int sweepIdx = -1;
      for(int i = 1; i < 50; i++) {
         if(iTime(m_symbol, m_tf, i) <= sweepTime) { sweepIdx = i; break; }
      }
      if(sweepIdx < 1) return false;
      int end = MathMin(sweepIdx + 14, iBars(m_symbol, m_tf) - 3);

      if(dir == DIR_BUY) {
         double best = 0;
         for(int i = sweepIdx; i <= end; i++) {
            double h = iHigh(m_symbol, m_tf, i);
            // Fractal high: higher than 2 bars on each side
            if(i >= 2 && i < iBars(m_symbol, m_tf) - 2)
               if(h > iHigh(m_symbol, m_tf, i-1) && h > iHigh(m_symbol, m_tf, i-2) &&
                  h > iHigh(m_symbol, m_tf, i+1) && h > iHigh(m_symbol, m_tf, i+2))
                  if(h > best) best = h;
         }
         if(best == 0)
            for(int i = sweepIdx; i <= end; i++) { double h = iHigh(m_symbol, m_tf, i); if(h > best) best = h; }
         level = best; return (best > 0);
      } else {
         double best = DBL_MAX;
         for(int i = sweepIdx; i <= end; i++) {
            double l = iLow(m_symbol, m_tf, i);
            if(i >= 2 && i < iBars(m_symbol, m_tf) - 2)
               if(l < iLow(m_symbol, m_tf, i-1) && l < iLow(m_symbol, m_tf, i-2) &&
                  l < iLow(m_symbol, m_tf, i+1) && l < iLow(m_symbol, m_tf, i+2))
                  if(l < best) best = l;
         }
         if(best == DBL_MAX)
            for(int i = sweepIdx; i <= end; i++) { double l = iLow(m_symbol, m_tf, i); if(l < best) best = l; }
         level = best; return (best < DBL_MAX);
      }
   }

   //==========================================================
   // FVG + CHoCH DETECTION WITH QUALITY GRADING
   //==========================================================
   bool FindFVGWithCHoCH(ENUM_SIGNAL_DIR dir, datetime sweepTime,
                         double structLevel, SFVG &fvg) {
      double atr     = GetATR(m_tf, 14);
      if(atr <= 0) return false;
      double minBody = atr * DISP_ATR_MULT;

      int bars = iBars(m_symbol, m_tf);
      int scan = MathMin(bars - 2, 30); // scan 30 M1 bars for CHoCH+FVG

      for(int i = scan - 1; i >= 2; i--) {
         datetime bt = iTime(m_symbol, m_tf, i);
         if(bt <= sweepTime) continue;

         double op = iOpen(m_symbol,  m_tf, i);
         double hi = iHigh(m_symbol,  m_tf, i);
         double lo = iLow(m_symbol,   m_tf, i);
         double cl = iClose(m_symbol, m_tf, i);
         double body = MathAbs(cl - op);

         if(dir == DIR_BUY) {
            if(cl <= op || body < minBody) continue; // not bullish displacement
            if(cl <= structLevel) continue;           // CHoCH not confirmed

            // True FVG: gap between previous bar high and next bar low
            if(i + 1 < scan) {
               double prevH = iHigh(m_symbol, m_tf, i+1);
               double nextL = iLow(m_symbol,  m_tf, i-1);
               if(prevH < nextL) {
                  fvg.isBullish = true;
                  fvg.lower     = prevH;
                  fvg.upper     = nextL;
                  fvg.midpoint  = (prevH + nextL) / 2.0;
                  fvg.time      = bt;
                  fvg.active    = true;
                  fvg.displacementBody = body;
                  fvg.touchCount = 0;
                  // Grade: A if body > 1.2×ATR and close is strong, B otherwise
                  fvg.grade = (body >= atr * 1.2 && (cl - lo) > body * 0.7) ? FVG_A : FVG_B;
                  return true;
               }
            }
            // Fallback: OB (last bearish bar before displacement)
            if(i + 1 < scan) {
               double obO = iOpen(m_symbol,  m_tf, i+1);
               double obC = iClose(m_symbol, m_tf, i+1);
               if(obC < obO && MathAbs(obO - obC) > atr * 0.2) {
                  fvg.isBullish = true;
                  fvg.lower     = obC;
                  fvg.upper     = obO;
                  fvg.midpoint  = (obC + obO) / 2.0;
                  fvg.time      = iTime(m_symbol, m_tf, i+1);
                  fvg.active    = true;
                  fvg.displacementBody = body;
                  fvg.touchCount = 0;
                  fvg.grade     = FVG_B;
                  return true;
               }
            }
         }

         if(dir == DIR_SELL) {
            if(cl >= op || body < minBody) continue;
            if(cl >= structLevel) continue;

            if(i + 1 < scan) {
               double prevL = iLow(m_symbol,  m_tf, i+1);
               double nextH = iHigh(m_symbol, m_tf, i-1);
               if(prevL > nextH) {
                  fvg.isBullish = false;
                  fvg.upper     = prevL;
                  fvg.lower     = nextH;
                  fvg.midpoint  = (prevL + nextH) / 2.0;
                  fvg.time      = bt;
                  fvg.active    = true;
                  fvg.displacementBody = body;
                  fvg.touchCount = 0;
                  fvg.grade = (body >= atr * 1.2 && (hi - cl) > body * 0.7) ? FVG_A : FVG_B;
                  return true;
               }
            }
            if(i + 1 < scan) {
               double obO = iOpen(m_symbol,  m_tf, i+1);
               double obC = iClose(m_symbol, m_tf, i+1);
               if(obC > obO && MathAbs(obO - obC) > atr * 0.2) {
                  fvg.isBullish = false;
                  fvg.upper     = obC;
                  fvg.lower     = obO;
                  fvg.midpoint  = (obC + obO) / 2.0;
                  fvg.time      = iTime(m_symbol, m_tf, i+1);
                  fvg.active    = true;
                  fvg.displacementBody = body;
                  fvg.touchCount = 0;
                  fvg.grade     = FVG_B;
                  return true;
               }
            }
         }
      }
      return false;
   }

   //==========================================================
   // BUILD SETUP FROM FVG
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
         Print("[", m_symbol, "] SL invalid: ", DoubleToString(slPips, 1), "p [", DoubleToString(minSL,1), "-", DoubleToString(maxSL,1), "]");
         return false;
      }

      // TP: find the nearest liquidity level beyond minDist
      double minTPDist = slDist * TARGET_RR;
      double tp;
      double liqTarget = FindLiqTarget(dir, entry, minTPDist);
      if(dir == DIR_BUY)
         tp = NormalizeDouble((liqTarget - entry >= minTPDist) ? liqTarget : entry + minTPDist, digits);
      else
         tp = NormalizeDouble((entry - liqTarget >= minTPDist) ? liqTarget : entry - minTPDist, digits);

      double rr = MathAbs(tp - entry) / slDist;

      m_setup.direction    = dir;
      m_setup.entryPrice   = entry;
      m_setup.stopLoss     = sl;
      m_setup.takeProfit   = tp;
      m_setup.riskReward   = rr;
      m_setup.slPips       = slPips;
      m_setup.fvg          = fvg;
      m_setup.sweepWickTip = wickTip;
      m_setup.session      = ses;
      m_setup.setupTime    = TimeCurrent();
      m_setup.lastArmTime  = 0;
      m_setup.phase        = PHASE_CONFIRMED;
      m_setup.entryFired   = false;
      m_setup.confluenceScore = 0; // set by QuantFilter
      m_setup.reason       = StringFormat("%s %s SL=%.1fp RR=1:%.1f",
                              (dir == DIR_BUY ? "BUY" : "SELL"), m_symbol, slPips, rr);

      Print("[", m_symbol, "] SETUP BUILT: ", m_setup.reason);
      return true;
   }

   double FindLiqTarget(ENUM_SIGNAL_DIR dir, double entry, double minDist) {
      int scan = MathMin(100, iBars(m_symbol, m_htf) - 1);
      if(dir == DIR_BUY) {
         for(int i = 1; i < scan; i++) {
            double h = iHigh(m_symbol, m_htf, i);
            if(h - entry >= minDist) return h;
         }
         return entry + minDist;
      } else {
         for(int i = 1; i < scan; i++) {
            double l = iLow(m_symbol, m_htf, i);
            if(entry - l >= minDist) return l;
         }
         return entry - minDist;
      }
   }

public:
   CSMCEngine(string symbol, ENUM_TIMEFRAMES tf, ENUM_TIMEFRAMES htf) {
      m_symbol = symbol; m_tf = tf; m_htf = htf;
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
   }

   //-----------------------------------------------------------
   // MAIN UPDATE — call once per new confirmed bar
   // Returns true when a setup is confirmed and ready
   //-----------------------------------------------------------
   bool Update(ENUM_SESSION session) {
      // Already confirmed — arm immediately
      if(m_setup.phase == PHASE_CONFIRMED) return true;

      // Scalping: allow all sessions EXCEPT hard weekends and dead Asian mid-hours
      // Map Asia during session; allow setups all day for M1 scalping
      bool activeSession = (session != SESSION_NONE);

      UpdateSwings();

      if(session == SESSION_ASIA) {
         MapAsiaLevels();
         // Still look for setups during Asia for scalping (not just mapping)
      }
      if(!activeSession) return false;

      // Bar cooldown check
      datetime curBar = iTime(m_symbol, m_tf, 0);
      if(m_lastTradeBar > 0) {
         int barsSince = (int)((curBar - m_lastTradeBar) / PeriodSeconds(m_tf));
         if(barsSince < MIN_BARS_BETWEEN) return false;
      }

      if(!SpreadOK()) return false;
      if(!m_asia.valid) MapAsiaLevels();

      // Time filter: avoid last 30 mins of NY (rollover risk)
      MqlDateTime dt; TimeToStruct(TimeGMT(), dt);
      if(dt.hour == 14 && dt.min >= 45) return false;

      ENUM_SIGNAL_DIR sweepDir = DIR_NONE;
      double wickTip = 0;
      datetime sweepTime = 0;

      // 1. Asia sweep priority
      bool swept = CheckAsiaSweep(sweepDir, wickTip, sweepTime);

      // 2. Swing sweep fallback
      if(!swept) swept = CheckSwingSweep(sweepDir, wickTip, sweepTime);

      if(!swept) return false;

      // 3. Find structure level
      double structLevel = 0;
      if(!FindStructureLevel(sweepDir, sweepTime, structLevel)) return false;

      // 4. Find FVG with confirmed CHoCH
      SFVG fvg; ZeroMemory(fvg);
      if(!FindFVGWithCHoCH(sweepDir, sweepTime, structLevel, fvg)) return false;
      if(fvg.grade == FVG_C) return false; // reject weak FVGs

      // 5. Build setup
      return BuildSetup(sweepDir, fvg, wickTip, session);
   }

   void ResetDay() {
      ZeroMemory(m_asia);
      if(m_setup.phase != PHASE_IN_TRADE)
         m_setup.phase = PHASE_IDLE;
   }

   void ResetSession() {
      if(m_setup.phase != PHASE_CONFIRMED && m_setup.phase != PHASE_IN_TRADE)
         m_setup.phase = PHASE_IDLE;
   }

   void OnTradePlaced() {
      m_lastTradeBar = iTime(m_symbol, m_tf, 0);
      m_setup.phase  = PHASE_IN_TRADE;
   }

   void OnTradeClose() {
      m_setup.phase     = PHASE_DONE;
      m_setup.entryFired = false;
   }

   void InvalidateSetup()  { m_setup.phase = PHASE_IDLE; ZeroMemory(m_setup); m_setup.phase = PHASE_IDLE; }

   SConfluenceSetup GetSetup()      { return m_setup; }
   SAsiaLevels      GetAsiaLevels() { return m_asia;  }
   bool             HasSetup()      { return (m_setup.phase == PHASE_CONFIRMED); }

   // Expose for age check in main EA
   void SetScore(int score) { m_setup.confluenceScore = score; }
};

#endif // SMCENGINE_V2_MQH
