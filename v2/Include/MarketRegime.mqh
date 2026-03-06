//+------------------------------------------------------------------+
//|                                              MarketRegime.mqh    |
//|         Institutional EA v2.2 — Market Regime & Bias Engine      |
//+------------------------------------------------------------------+
#ifndef MARKETREGIME_V2_MQH
#define MARKETREGIME_V2_MQH

#include "Defines.mqh"

class CMarketRegime {
private:
   string            m_symbol;
   double            m_pipSize;
   bool              m_isGold;
   bool              m_isJPY;
   bool              m_isBTC;
   SMarketRegime     m_cached;
   datetime          m_lastUpdate;

   //-----------------------------------------------------------
   // GET ATR
   //-----------------------------------------------------------
   double GetATR(ENUM_TIMEFRAMES tf, int period) {
      double buf[];
      ArraySetAsSeries(buf, true);
      int h = iATR(m_symbol, tf, period);
      if(h == INVALID_HANDLE) return 0;
      int c = CopyBuffer(h, 0, 0, period + 2, buf);
      IndicatorRelease(h);
      if(c < 2) return 0;
      return buf[1];
   }

   //-----------------------------------------------------------
   // FRACTAL SWING BIAS on a single timeframe
   //-----------------------------------------------------------
   ENUM_HTF_BIAS GetSwingBias(ENUM_TIMEFRAMES tf) {
      int lb    = 2;
      int total = iBars(m_symbol, tf);
      int scan  = MathMin(total - lb - 1, 50);
      if(scan < lb + 3) return BIAS_NONE;

      double sh[3], sl[3];
      int    shC = 0, slC = 0;
      ArrayInitialize(sh, 0); ArrayInitialize(sl, 0);

      for(int i = lb; i < scan && (shC < 3 || slC < 3); i++) {
         if(shC < 3) {
            double hi = iHigh(m_symbol, tf, i);
            bool ok = true;
            for(int j = 1; j <= lb && ok; j++)
               if(iHigh(m_symbol, tf, i-j) >= hi || iHigh(m_symbol, tf, i+j) >= hi)
                  ok = false;
            if(ok) sh[shC++] = hi;
         }
         if(slC < 3) {
            double lo = iLow(m_symbol, tf, i);
            bool ok = true;
            for(int j = 1; j <= lb && ok; j++)
               if(iLow(m_symbol, tf, i-j) <= lo || iLow(m_symbol, tf, i+j) <= lo)
                  ok = false;
            if(ok) sl[slC++] = lo;
         }
      }

      if(shC >= 2 && slC >= 2) {
         bool higherHighs = (sh[0] > sh[1]);
         bool higherLows  = (sl[0] > sl[1]);
         bool lowerHighs  = (sh[0] < sh[1]);
         bool lowerLows   = (sl[0] < sl[1]);

         if(higherHighs && higherLows) return BIAS_BULLISH;
         if(lowerHighs  && lowerLows)  return BIAS_BEARISH;
      }
      return BIAS_NONE;
   }

   //-----------------------------------------------------------
   // VOLATILITY REGIME via ATR ratio
   //-----------------------------------------------------------
   ENUM_VOLATILITY GetVolatility() {
      double atrNow = GetATR(PERIOD_H1, 14);
      double atrAvg = 0;
      double sum    = 0;
      double buf[];
      ArraySetAsSeries(buf, true);
      int h = iATR(m_symbol, PERIOD_H1, 14);
      if(h == INVALID_HANDLE) return VOL_NORMAL;
      int c = CopyBuffer(h, 0, 1, 50, buf);
      IndicatorRelease(h);
      if(c < 10) return VOL_NORMAL;
      for(int i = 0; i < c; i++) sum += buf[i];
      atrAvg = sum / c;
      if(atrAvg <= 0) return VOL_NORMAL;

      double ratio = atrNow / atrAvg;
      if(ratio < 0.5)  return VOL_LOW;
      if(ratio < 1.4)  return VOL_NORMAL;
      if(ratio < 2.0)  return VOL_HIGH;
      return VOL_EXTREME;
   }

   //-----------------------------------------------------------
   // CHOPPY DETECTION
   //-----------------------------------------------------------
   bool IsChoppy(ENUM_TIMEFRAMES tf, int bars = 8) {
      int total = iBars(m_symbol, tf);
      if(total < bars + 2) return false;
      double wickBodyRatioSum = 0;
      for(int i = 1; i <= bars; i++) {
         double op = iOpen(m_symbol,  tf, i);
         double cl = iClose(m_symbol, tf, i);
         double hi = iHigh(m_symbol,  tf, i);
         double lo = iLow(m_symbol,   tf, i);
         double body = MathAbs(cl - op);
         double range = hi - lo;
         if(range <= 0) continue;
         double wick = range - body;
         wickBodyRatioSum += (wick / range);
      }
      double avgRatio = wickBodyRatioSum / bars;
      return (avgRatio > 0.72);
   }

   //-----------------------------------------------------------
   // TREND REGIME 
   //-----------------------------------------------------------
   ENUM_REGIME DetermineRegime() {
      if(IsChoppy(PERIOD_M15, 10)) return REGIME_CHOPPY;
      ENUM_VOLATILITY vol = GetVolatility();
      if(vol == VOL_LOW) return REGIME_RANGING;

      ENUM_HTF_BIAS b1 = GetSwingBias(PERIOD_H1);
      ENUM_HTF_BIAS b15 = GetSwingBias(PERIOD_M15);
      
      if(b1 == BIAS_BULLISH && b15 == BIAS_BULLISH) return REGIME_TRENDING_UP;
      if(b1 == BIAS_BEARISH && b15 == BIAS_BEARISH) return REGIME_TRENDING_DOWN;
      if(b1 == BIAS_NONE    && b15 == BIAS_NONE)    return REGIME_RANGING;
      return REGIME_RANGING;
   }

public:
   CMarketRegime(string symbol) {
      m_symbol   = symbol;
      m_isGold   = (StringFind(symbol, "XAU") >= 0 || StringFind(symbol, "GOLD") >= 0);
      m_isJPY    = (StringFind(symbol, "JPY") >= 0);
      m_isBTC    = (StringFind(symbol, "BTC") >= 0);
      if(m_isGold)      m_pipSize = 0.10;
      else if(m_isJPY)  m_pipSize = 0.01;
      else if(m_isBTC)  m_pipSize = 1.0;
      else              m_pipSize = 0.0001;
      ZeroMemory(m_cached);
      m_cached.regime    = REGIME_RANGING;
      m_cached.bias      = BIAS_NONE;
      m_cached.volatility = VOL_NORMAL;
      m_lastUpdate = 0;
   }

   //-----------------------------------------------------------
   // UPDATE REGIME (call once per new bar)
   //-----------------------------------------------------------
   void Update() {
      datetime barT = iTime(m_symbol, PERIOD_M5, 0);
      if(barT == m_lastUpdate) return;
      m_lastUpdate = barT;

      ENUM_HTF_BIAS bH1 = GetSwingBias(PERIOD_H1);
      ENUM_HTF_BIAS bM15= GetSwingBias(PERIOD_M15);

      if(bH1 == BIAS_BULLISH && bM15 == BIAS_BULLISH) { 
         m_cached.bias = BIAS_BULLISH; m_cached.biasStrong = true;
      }
      else if(bH1 == BIAS_BEARISH && bM15 == BIAS_BEARISH) { 
         m_cached.bias = BIAS_BEARISH; m_cached.biasStrong = true;
      }
      else if(bH1 == BIAS_BULLISH || bM15 == BIAS_BULLISH) { 
         m_cached.bias = BIAS_BULLISH; m_cached.biasStrong = false;
      }
      else if(bH1 == BIAS_BEARISH || bM15 == BIAS_BEARISH) { 
         m_cached.bias = BIAS_BEARISH; m_cached.biasStrong = false;
      }
      else { 
         m_cached.bias = BIAS_CONFLICT; m_cached.biasStrong = false;
      }

      m_cached.volatility = GetVolatility();
      m_cached.regime     = DetermineRegime();
   }

   SMarketRegime  GetRegime()      { return m_cached; }
   ENUM_HTF_BIAS  GetBias()        { return m_cached.bias; }
   bool           IsBiasStrong()   { return m_cached.biasStrong; }
   ENUM_VOLATILITY GetVolTier()    { return m_cached.volatility; }
   bool           IsChoppyNow()    { return (m_cached.regime == REGIME_CHOPPY); }

   static ENUM_SESSION GetSession() {
      MqlDateTime dt;
      TimeToStruct(TimeGMT(), dt);
      int h = dt.hour;
      if(h >= ASIA_GMT_START    && h < ASIA_GMT_END)    return SESSION_ASIA;
      if(h >= LONDON_GMT_START  && h < LONDON_GMT_END)  return SESSION_LONDON;
      if(h >= OVERLAP_GMT_START && h < OVERLAP_GMT_END) return SESSION_LONDON_NY;
      if(h >= NY_GMT_START      && h < NY_GMT_END)      return SESSION_NY;
      return SESSION_OTHER;
   }

   static string SessionName(ENUM_SESSION s) {
      switch(s) {
         case SESSION_ASIA:      return "ASIA";
         case SESSION_LONDON:    return "LONDON KILL";
         case SESSION_LONDON_NY: return "OVERLAP";
         case SESSION_NY:        return "NY KILL";
         default:                return "OFF";
      }
   }

   double PipSize() { return m_pipSize; }
   double GetATRPublic(ENUM_TIMEFRAMES tf, int p = 14) { return GetATR(tf, p); }
};

#endif // MARKETREGIME_V2_MQH