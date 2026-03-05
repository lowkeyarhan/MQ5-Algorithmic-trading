//+------------------------------------------------------------------+
//|                                               SilverBullet.mqh  |
//|         SMC Structure + Liquidity Sweep Scalp Engine v4.0       |
//+------------------------------------------------------------------+
#ifndef SILVERBULLET_MQH
#define SILVERBULLET_MQH

#include "Defines.mqh"

class CSilverBullet {
private:
   string           m_symbol;
   ENUM_TIMEFRAMES  m_tf;
   ENUM_TIMEFRAMES  m_htf;
   ENUM_TIMEFRAMES  m_biasTF;

   SAsiaLevels      m_asia;
   SSetup           m_setup;
   bool             m_isGold;
   bool             m_isJPY;
   bool             m_isBTC;
   double           m_pipSize;
   int              m_gmtOffsetSec;

   double PipsToPrice(double pips) {
      return pips * m_pipSize;
   }

   double PriceToPips(double priceDistance) {
      if(m_pipSize <= 0) return 0;
      return priceDistance / m_pipSize;
   }

   int DetectGMTOffset() {
      datetime gmt    = TimeGMT();
      datetime server = TimeCurrent();
      return (int)(server - gmt);
   }

   datetime ServerToGMT(datetime serverTime) {
      return serverTime - m_gmtOffsetSec;
   }

   void ServerTimeToGMTComponents(datetime serverTime, int &hour, int &minute) {
      datetime gmt = ServerToGMT(serverTime);
      MqlDateTime dt;
      TimeToStruct(gmt, dt);
      hour   = dt.hour;
      minute = dt.min;
   }

   void GetGMT(int &hour, int &minute) {
      MqlDateTime dt;
      TimeToStruct(TimeGMT(), dt);
      hour   = dt.hour;
      minute = dt.min;
   }

   datetime GetGMTDate() {
      MqlDateTime dt;
      TimeToStruct(TimeGMT(), dt);
      dt.hour = 0; dt.min = 0; dt.sec = 0;
      return StructToTime(dt);
   }

   ENUM_SESSION GetCurrentSession() {
      int h, m;
      GetGMT(h, m);
      if(h >= LONDON_KILL_H_START && h < LONDON_KILL_H_END)
         return SESSION_LONDON_KILL;
      if(h >= NY_KILL_H_START && h < NY_KILL_H_END)
         return SESSION_NY_KILL;
      if(h >= ASIA_H_START && h < ASIA_H_END)
         return SESSION_ASIA;
      return SESSION_OTHER;
   }

   double GetATR(ENUM_TIMEFRAMES tf, int period=14) {
      double buf[];
      ArraySetAsSeries(buf, true);
      int h = iATR(m_symbol, tf, period);
      if(h == INVALID_HANDLE) return 0;
      int copied = CopyBuffer(h, 0, 0, 3, buf);
      IndicatorRelease(h);
      if(copied < 2) return 0;
      return buf[1];
   }

   ENUM_HTF_BIAS GetH1Bias() {
      double h1Close1 = iClose(m_symbol, m_biasTF, 1);
      double h1Close2 = iClose(m_symbol, m_biasTF, 2);
      double h1Close3 = iClose(m_symbol, m_biasTF, 3);
      double h1High1  = iHigh(m_symbol, m_biasTF, 1);
      double h1Low1   = iLow(m_symbol, m_biasTF, 1);
      double h1High2  = iHigh(m_symbol, m_biasTF, 2);
      double h1Low2   = iLow(m_symbol, m_biasTF, 2);

      if(h1Close1 <= 0 || h1Close2 <= 0) return BIAS_NONE;

      bool hh = (h1High1 > h1High2);
      bool hl = (h1Low1  > h1Low2);
      bool lh = (h1High1 < h1High2);
      bool ll = (h1Low1  < h1Low2);

      double ema[];
      ArraySetAsSeries(ema, true);
      int emaH = iMA(m_symbol, m_biasTF, 21, 0, MODE_EMA, PRICE_CLOSE);
      if(emaH != INVALID_HANDLE) {
         if(CopyBuffer(emaH, 0, 0, 3, ema) >= 2) {
            IndicatorRelease(emaH);
            bool aboveEMA = (h1Close1 > ema[1]);
            bool belowEMA = (h1Close1 < ema[1]);

            if((hh && hl) || (hh && aboveEMA) || (hl && aboveEMA))
               return BIAS_BULLISH;
            if((lh && ll) || (lh && belowEMA) || (ll && belowEMA))
               return BIAS_BEARISH;

            if(aboveEMA) return BIAS_BULLISH;
            if(belowEMA) return BIAS_BEARISH;
         } else {
            IndicatorRelease(emaH);
         }
      }

      if(h1Close1 > h1Close3) return BIAS_BULLISH;
      if(h1Close1 < h1Close3) return BIAS_BEARISH;

      return BIAS_NONE;
   }

   void MapAsiaLevels() {
      datetime today = GetGMTDate();
      if(m_asia.valid && m_asia.date == today) return;

      m_asia.high      = -1;
      m_asia.low       = -1;
      m_asia.valid     = false;
      m_asia.highSwept = false;
      m_asia.lowSwept  = false;
      m_asia.date      = today;

      int bars = iBars(m_symbol, m_tf);
      if(bars < 10) return;
      int maxScan = MathMin(bars - 1, 500);
      int counted = 0;

      for(int i = 1; i <= maxScan; i++) {
         datetime barTime = iTime(m_symbol, m_tf, i);
         if(barTime <= 0) continue;

         int gmtH, gmtM;
         ServerTimeToGMTComponents(barTime, gmtH, gmtM);

         datetime barGMT = ServerToGMT(barTime);
         MqlDateTime barDt;
         TimeToStruct(barGMT, barDt);
         barDt.hour = 0; barDt.min = 0; barDt.sec = 0;
         datetime barDate = StructToTime(barDt);

         if(barDate != today) {
            if(counted > 0) break;
            continue;
         }

         if(gmtH >= ASIA_H_START && gmtH < ASIA_H_END) {
            double h = iHigh(m_symbol, m_tf, i);
            double l = iLow(m_symbol,  m_tf, i);
            if(m_asia.high < 0 || h > m_asia.high) { m_asia.high = h; m_asia.highTime = barTime; }
            if(m_asia.low  < 0 || l < m_asia.low)  { m_asia.low  = l; m_asia.lowTime  = barTime; }
            counted++;
         }
      }

      if(counted >= 3 && m_asia.high > 0 && m_asia.low > 0 && m_asia.high > m_asia.low) {
         m_asia.valid = true;
         double range = PriceToPips(m_asia.high - m_asia.low);
         Print("[", m_symbol, "] Asia mapped: High=", DoubleToString(m_asia.high, 5),
               " Low=", DoubleToString(m_asia.low, 5),
               " Range=", DoubleToString(range, 1), " pips (",
               IntegerToString(counted), " bars)");
      } else {
         Print("[", m_symbol, "] Asia mapping incomplete: counted=", IntegerToString(counted));
      }
   }

   bool CheckSweep(ENUM_SIGNAL_DIRECTION &sweepDir) {
      if(!m_asia.valid) return false;

      double sweepMin, sweepMax;
      if(m_isGold) {
         sweepMin = PipsToPrice(SWEEP_MIN_PIPS_GOLD);
         sweepMax = PipsToPrice(SWEEP_MAX_PIPS_GOLD);
      } else if(m_isJPY) {
         sweepMin = PipsToPrice(SWEEP_MIN_PIPS_JPY);
         sweepMax = PipsToPrice(SWEEP_MAX_PIPS_JPY);
      } else {
         sweepMin = PipsToPrice(SWEEP_MIN_PIPS_FX);
         sweepMax = PipsToPrice(SWEEP_MAX_PIPS_FX);
      }

      int barsToCheck = MathMin(5, iBars(m_symbol, m_tf) - 1);

      for(int i = 1; i <= barsToCheck; i++) {
         double high_i  = iHigh(m_symbol,  m_tf, i);
         double low_i   = iLow(m_symbol,   m_tf, i);
         double close_i = iClose(m_symbol, m_tf, i);

         if(!m_asia.highSwept) {
            double pierce = high_i - m_asia.high;
            if(pierce >= sweepMin && pierce <= sweepMax) {
               if(close_i <= m_asia.high) {
                  m_asia.highSwept    = true;
                  m_asia.sweepWickTip = high_i;
                  m_asia.sweepTime    = iTime(m_symbol, m_tf, i);
                  sweepDir            = SIGNAL_SELL;
                  Print("[", m_symbol, "] SELL SWEEP bar[", IntegerToString(i),
                        "]: AsiaHi=", DoubleToString(m_asia.high, 5),
                        " wick=", DoubleToString(high_i, 5),
                        " close=", DoubleToString(close_i, 5));
                  return true;
               }
            }
         }

         if(!m_asia.lowSwept) {
            double pierce = m_asia.low - low_i;
            if(pierce >= sweepMin && pierce <= sweepMax) {
               if(close_i >= m_asia.low) {
                  m_asia.lowSwept     = true;
                  m_asia.sweepWickTip = low_i;
                  m_asia.sweepTime    = iTime(m_symbol, m_tf, i);
                  sweepDir            = SIGNAL_BUY;
                  Print("[", m_symbol, "] BUY SWEEP bar[", IntegerToString(i),
                        "]: AsiaLo=", DoubleToString(m_asia.low, 5),
                        " wick=", DoubleToString(low_i, 5),
                        " close=", DoubleToString(close_i, 5));
                  return true;
               }
            }
         }
      }
      return false;
   }

   bool DetectCHoCHandFVG(ENUM_SIGNAL_DIRECTION dir, SFVG &fvg) {
      double atr = GetATR(m_tf, 14);
      if(atr <= 0) {
         Print("[", m_symbol, "] ATR unavailable");
         return false;
      }

      double minBody = atr * DISP_ATR_MULT;
      int maxBars = MathMin(iBars(m_symbol, m_tf) - 2, 20);

      for(int i = 1; i < maxBars; i++) {
         datetime barT = iTime(m_symbol, m_tf, i);
         if(barT <= m_asia.sweepTime) continue;

         double open_i  = iOpen(m_symbol,  m_tf, i);
         double high_i  = iHigh(m_symbol,  m_tf, i);
         double low_i   = iLow(m_symbol,   m_tf, i);
         double close_i = iClose(m_symbol, m_tf, i);
         double body    = MathAbs(close_i - open_i);

         if(dir == SIGNAL_BUY) {
            if(close_i <= open_i) continue;
            if(body < minBody) continue;

            if(i + 1 < maxBars && i - 1 >= 0) {
               double prevHigh = iHigh(m_symbol, m_tf, i + 1);
               double nextLow  = iLow(m_symbol,  m_tf, i - 1);
               if(prevHigh < nextLow) {
                  fvg.isBullish = true;
                  fvg.lower     = prevHigh;
                  fvg.upper     = nextLow;
                  fvg.midpoint  = (fvg.lower + fvg.upper) / 2.0;
                  fvg.time      = barT;
                  fvg.active    = true;
                  Print("[", m_symbol, "] BUY FVG bar[", IntegerToString(i),
                        "]: ", DoubleToString(fvg.lower, 5),
                        "-", DoubleToString(fvg.upper, 5));
                  return true;
               }
            }

            for(int j = i + 1; j < i + 5 && j < maxBars; j++) {
               double ob_open  = iOpen(m_symbol,  m_tf, j);
               double ob_close = iClose(m_symbol, m_tf, j);
               double ob_low   = iLow(m_symbol,   m_tf, j);
               if(ob_close < ob_open) {
                  fvg.isBullish = true;
                  fvg.lower     = ob_low;
                  fvg.upper     = ob_open;
                  fvg.midpoint  = (ob_low + ob_open) / 2.0;
                  fvg.time      = iTime(m_symbol, m_tf, j);
                  fvg.active    = true;
                  Print("[", m_symbol, "] BUY OB bar[", IntegerToString(j), "]");
                  return true;
               }
            }

            fvg.isBullish = true;
            fvg.lower     = low_i;
            fvg.upper     = low_i + (high_i - low_i) * 0.5;
            fvg.midpoint  = low_i + (high_i - low_i) * 0.382;
            fvg.time      = barT;
            fvg.active    = true;
            Print("[", m_symbol, "] BUY OTE fallback bar[", IntegerToString(i), "]");
            return true;
         }

         if(dir == SIGNAL_SELL) {
            if(close_i >= open_i) continue;
            if(body < minBody) continue;

            if(i + 1 < maxBars && i - 1 >= 0) {
               double prevLow  = iLow(m_symbol,  m_tf, i + 1);
               double nextHigh = iHigh(m_symbol, m_tf, i - 1);
               if(prevLow > nextHigh) {
                  fvg.isBullish = false;
                  fvg.upper     = prevLow;
                  fvg.lower     = nextHigh;
                  fvg.midpoint  = (fvg.upper + fvg.lower) / 2.0;
                  fvg.time      = barT;
                  fvg.active    = true;
                  Print("[", m_symbol, "] SELL FVG bar[", IntegerToString(i),
                        "]: ", DoubleToString(fvg.lower, 5),
                        "-", DoubleToString(fvg.upper, 5));
                  return true;
               }
            }

            for(int j = i + 1; j < i + 5 && j < maxBars; j++) {
               double ob_open  = iOpen(m_symbol,  m_tf, j);
               double ob_close = iClose(m_symbol, m_tf, j);
               double ob_high  = iHigh(m_symbol,  m_tf, j);
               if(ob_close > ob_open) {
                  fvg.isBullish = false;
                  fvg.upper     = ob_high;
                  fvg.lower     = ob_open;
                  fvg.midpoint  = (ob_high + ob_open) / 2.0;
                  fvg.time      = iTime(m_symbol, m_tf, j);
                  fvg.active    = true;
                  Print("[", m_symbol, "] SELL OB bar[", IntegerToString(j), "]");
                  return true;
               }
            }

            fvg.isBullish = false;
            fvg.upper     = high_i;
            fvg.lower     = high_i - (high_i - low_i) * 0.5;
            fvg.midpoint  = high_i - (high_i - low_i) * 0.382;
            fvg.time      = barT;
            fvg.active    = true;
            Print("[", m_symbol, "] SELL OTE fallback bar[", IntegerToString(i), "]");
            return true;
         }
      }
      return false;
   }

   bool SpreadOK() {
      double spreadPoints = (double)SymbolInfoInteger(m_symbol, SYMBOL_SPREAD)
                            * SymbolInfoDouble(m_symbol, SYMBOL_POINT);
      double spreadPips   = PriceToPips(spreadPoints);

      double maxPips;
      if(m_isGold)     maxPips = MAX_SPREAD_PIPS_GOLD;
      else if(m_isBTC) maxPips = MAX_SPREAD_PIPS_BTC;
      else             maxPips = MAX_SPREAD_PIPS_FX;

      if(spreadPips > maxPips) {
         Print("[", m_symbol, "] Spread too wide: ",
               DoubleToString(spreadPips, 1), " pips (max ",
               DoubleToString(maxPips, 1), ")");
         return false;
      }
      return true;
   }

   double FindLiquidityTarget(ENUM_SIGNAL_DIRECTION dir, double entry, double minTPDist) {
      int barsToScan = MathMin(100, iBars(m_symbol, m_htf) - 1);
      if(dir == SIGNAL_BUY) {
         double bestTarget = entry + minTPDist;
         for(int i = 1; i < barsToScan; i++) {
            double h = iHigh(m_symbol, m_htf, i);
            if(h > entry + minTPDist * 0.8 && h > entry) {
               if(h - entry >= minTPDist) { bestTarget = h; break; }
            }
         }
         return bestTarget;
      } else {
         double bestTarget = entry - minTPDist;
         for(int i = 1; i < barsToScan; i++) {
            double l = iLow(m_symbol, m_htf, i);
            if(l < entry - minTPDist * 0.8 && l < entry) {
               if(entry - l >= minTPDist) { bestTarget = l; break; }
            }
         }
         return bestTarget;
      }
   }

   bool BuildSetup(ENUM_SIGNAL_DIRECTION dir, SFVG &fvg, ENUM_SESSION session) {
      int    digits = (int)SymbolInfoInteger(m_symbol, SYMBOL_DIGITS);
      double point  = SymbolInfoDouble(m_symbol, SYMBOL_POINT);
      double entry  = NormalizeDouble(fvg.midpoint, digits);
      double sl;

      double buffer = PipsToPrice(0.5);
      if(m_isGold) buffer = PipsToPrice(1.0);

      if(dir == SIGNAL_BUY) {
         sl = NormalizeDouble(m_asia.sweepWickTip - buffer, digits);
         if(entry <= sl) {
            Print("[", m_symbol, "] BUY rejected: entry<=SL");
            return false;
         }
      } else {
         sl = NormalizeDouble(m_asia.sweepWickTip + buffer, digits);
         if(entry >= sl) {
            Print("[", m_symbol, "] SELL rejected: entry>=SL");
            return false;
         }
      }

      double slDist = MathAbs(entry - sl);
      double slPips = PriceToPips(slDist);

      double maxSL;
      if(m_isGold)      maxSL = MAX_SL_PIPS_GOLD;
      else if(m_isBTC)  maxSL = MAX_SL_PIPS_BTC;
      else if(m_isJPY)  maxSL = MAX_SL_PIPS_JPY;
      else              maxSL = MAX_SL_PIPS_FOREX;

      if(slPips > maxSL) {
         Print("[", m_symbol, "] SL too wide: ", DoubleToString(slPips, 1), " pips");
         return false;
      }
      if(slPips < 0.3) {
         Print("[", m_symbol, "] SL too tight: ", DoubleToString(slPips, 1), " pips");
         return false;
      }

      double minTPDist = slDist * TARGET_RR;
      double liqTarget = FindLiquidityTarget(dir, entry, minTPDist);
      double tp;

      if(dir == SIGNAL_BUY) {
         double liqDist = liqTarget - entry;
         if(liqDist >= minTPDist)
            tp = NormalizeDouble(liqTarget, digits);
         else
            tp = NormalizeDouble(entry + minTPDist, digits);
      } else {
         double liqDist = entry - liqTarget;
         if(liqDist >= minTPDist)
            tp = NormalizeDouble(liqTarget, digits);
         else
            tp = NormalizeDouble(entry - minTPDist, digits);
      }

      double actualRR = MathAbs(tp - entry) / slDist;

      m_setup.direction   = dir;
      m_setup.entryPrice  = entry;
      m_setup.stopLoss    = sl;
      m_setup.takeProfit  = tp;
      m_setup.riskReward  = actualRR;
      m_setup.slPips      = slPips;
      m_setup.fvg         = fvg;
      m_setup.fvgFound    = true;
      m_setup.chochDone   = true;
      m_setup.session     = session;
      m_setup.setupTime   = TimeCurrent();
      m_setup.phase       = PHASE_CONFIRMED;

      string sesName = (session == SESSION_LONDON_KILL) ? "London" : "NY";
      string fvgType = fvg.active ? "FVG" : "OB";
      m_setup.reason = sesName + " sweep+CHoCH+" + fvgType
                     + " SL=" + DoubleToString(slPips, 1) + "pips"
                     + " RR=1:" + DoubleToString(actualRR, 1);

      string dirStr = (dir == SIGNAL_BUY) ? "BUY" : "SELL";
      Print("[", m_symbol, "] === SETUP CONFIRMED ===");
      Print("[", m_symbol, "] ", dirStr,
            " Entry=", DoubleToString(entry, digits),
            " SL=", DoubleToString(sl, digits),
            " TP=", DoubleToString(tp, digits),
            " SLpips=", DoubleToString(slPips, 1),
            " RR=1:", DoubleToString(actualRR, 1));
      return true;
   }

public:
   CSilverBullet(string symbol, ENUM_TIMEFRAMES tf, ENUM_TIMEFRAMES htf) {
      m_symbol  = symbol;
      m_tf      = tf;
      m_htf     = htf;
      m_biasTF  = PERIOD_H1;

      m_isGold = (StringFind(symbol, "XAU") >= 0 || StringFind(symbol, "GOLD") >= 0);
      m_isJPY  = (StringFind(symbol, "JPY") >= 0);
      m_isBTC  = (StringFind(symbol, "BTC") >= 0);

      if(m_isGold)     m_pipSize = 0.10;
      else if(m_isJPY) m_pipSize = 0.01;
      else if(m_isBTC) m_pipSize = 1.0;
      else             m_pipSize = 0.0001;

      m_gmtOffsetSec = DetectGMTOffset();

      ZeroMemory(m_asia);
      ZeroMemory(m_setup);
      m_setup.phase = PHASE_IDLE;

      Print("[", symbol, "] Engine init: pipSize=", DoubleToString(m_pipSize, 5),
            " gmtOffset=", IntegerToString(m_gmtOffsetSec/3600), "h",
            " gold=", (m_isGold?"Y":"N"),
            " jpy=", (m_isJPY?"Y":"N"));
   }

   bool Update() {
      ENUM_SESSION session = GetCurrentSession();

      if(session == SESSION_ASIA) {
         MapAsiaLevels();
         if(m_setup.phase == PHASE_IDLE)
            m_setup.phase = PHASE_WATCHING;
         return false;
      }

      if(session != SESSION_LONDON_KILL && session != SESSION_NY_KILL)
         return false;

      if(m_setup.phase == PHASE_CONFIRMED || m_setup.phase == PHASE_IN_TRADE)
         return false;

      if(!m_asia.valid) {
         MapAsiaLevels();
         if(!m_asia.valid) return false;
      }

      if(!SpreadOK()) return false;

      ENUM_HTF_BIAS bias = GetH1Bias();

      if(m_setup.phase == PHASE_WATCHING || m_setup.phase == PHASE_IDLE ||
         m_setup.phase == PHASE_DONE) {
         ENUM_SIGNAL_DIRECTION sweepDir = SIGNAL_NONE;
         if(CheckSweep(sweepDir)) {
            if(bias != BIAS_NONE) {
               if(sweepDir == SIGNAL_BUY && bias == BIAS_BEARISH)
                  Print("[", m_symbol, "] BUY sweep vs BEARISH H1 bias - caution");
               if(sweepDir == SIGNAL_SELL && bias == BIAS_BULLISH)
                  Print("[", m_symbol, "] SELL sweep vs BULLISH H1 bias - caution");
            }
            m_setup.direction = sweepDir;
            m_setup.phase     = PHASE_SWEPT;
         }
      }

      if(m_setup.phase == PHASE_SWEPT) {
         SFVG fvg;
         ZeroMemory(fvg);
         if(DetectCHoCHandFVG(m_setup.direction, fvg)) {
            if(BuildSetup(m_setup.direction, fvg, session))
               return true;
         }

         int barsSinceSweep = 0;
         if(m_asia.sweepTime > 0)
            barsSinceSweep = (int)((TimeCurrent() - m_asia.sweepTime) / PeriodSeconds(m_tf));

         if(barsSinceSweep > MAX_BARS_AFTER_SWEEP) {
            Print("[", m_symbol, "] CHoCH timeout after ", IntegerToString(barsSinceSweep), " bars");
            m_setup.phase = PHASE_WATCHING;
            if(m_setup.direction == SIGNAL_BUY)  m_asia.lowSwept  = false;
            if(m_setup.direction == SIGNAL_SELL) m_asia.highSwept = false;
         }
      }

      return false;
   }

   SSetup       GetSetup()       { return m_setup; }
   SAsiaLevels  GetAsiaLevels()  { return m_asia; }
   bool         HasSetup()       { return (m_setup.phase == PHASE_CONFIRMED); }
   bool         IsInKillzone()   {
      ENUM_SESSION s = GetCurrentSession();
      return (s == SESSION_LONDON_KILL || s == SESSION_NY_KILL);
   }
   ENUM_SESSION GetSession()     { return GetCurrentSession(); }
   string       GetSessionName() {
      switch(GetCurrentSession()) {
         case SESSION_LONDON_KILL: return "London Killzone";
         case SESSION_NY_KILL:     return "NY Killzone";
         case SESSION_ASIA:        return "Asia (Mapping)";
         default:                  return "Off-Session";
      }
   }

   void OnTradePlaced() { m_setup.phase = PHASE_IN_TRADE; }

   void OnTradeClose() { m_setup.phase = PHASE_WATCHING; }

   void ResetSession() {
      m_setup.phase = PHASE_WATCHING;
      m_asia.highSwept = false;
      m_asia.lowSwept  = false;
      Print("[", m_symbol, "] Session reset");
   }

   void ResetDay() {
      ZeroMemory(m_asia);
      ZeroMemory(m_setup);
      m_setup.phase = PHASE_IDLE;
      m_gmtOffsetSec = DetectGMTOffset();
      Print("[", m_symbol, "] New day reset");
   }

   bool IsFVGStillValid() {
      if(m_setup.phase != PHASE_CONFIRMED) return false;
      double bid = SymbolInfoDouble(m_symbol, SYMBOL_BID);
      if(m_setup.direction == SIGNAL_BUY)
         return (bid > m_setup.stopLoss);
      else
         return (bid < m_setup.stopLoss);
   }

   double GetCurrentATR() { return GetATR(m_tf, 14); }
};

#endif
