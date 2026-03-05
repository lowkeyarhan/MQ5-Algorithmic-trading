//+------------------------------------------------------------------+
//|                                               SilverBullet.mqh  |
//|         SMC Structure + Liquidity Sweep Scalp Engine v7.0       |
//|                                                                  |
//|  v7.0 COMPLETE OVERHAUL -- Quality over quantity:               |
//|  - CHoCH/BOS REQUIRED after every sweep (biggest win rate fix)  |
//|  - H1 bias using swing structure (HH/HL/LH/LL), not EMA noise  |
//|  - H1 OR M15 bias required for ALL trades (Asia + Swing)       |
//|  - FVG-only entries with proper OB fallback (no random candles) |
//|  - FVG search from sweep forward (closest to sweep = best RR)  |
//|  - Asia range filter (reject noise/overextended sessions)       |
//|  - Tighter displacement (0.7x ATR), sweep thresholds, spreads  |
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

   SSwingPoint      m_swingHighs[];
   SSwingPoint      m_swingLows[];
   int              m_shCount;
   int              m_slCount;
   datetime         m_lastSwingUpdate;
   datetime         m_lastTradeBar;

   double PipsToPrice(double pips)      { return pips * m_pipSize; }
   double PriceToPips(double priceDist) {
      if(m_pipSize <= 0) return 0;
      return priceDist / m_pipSize;
   }

   int DetectGMTOffset() {
      return (int)(TimeCurrent() - TimeGMT());
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

   //==========================================================
   // H1 BIAS -- swing structure analysis (HH/HL = bull, LH/LL = bear)
   //==========================================================
   ENUM_HTF_BIAS GetH1Bias() {
      int lb = 3;
      int maxBars = MathMin(iBars(m_symbol, m_biasTF) - lb - 1, 60);
      if(maxBars < lb + 3) return BIAS_NONE;

      double sh[];
      double sl[];
      ArrayResize(sh, 2);
      ArrayResize(sl, 2);
      int shC = 0, slC = 0;

      for(int i = lb; i < maxBars && (shC < 2 || slC < 2); i++) {
         double hi = iHigh(m_symbol, m_biasTF, i);
         if(shC < 2) {
            bool isSwH = true;
            for(int j = 1; j <= lb; j++) {
               if(iHigh(m_symbol, m_biasTF, i - j) >= hi ||
                  iHigh(m_symbol, m_biasTF, i + j) >= hi) {
                  isSwH = false; break;
               }
            }
            if(isSwH) sh[shC++] = hi;
         }

         double lo = iLow(m_symbol, m_biasTF, i);
         if(slC < 2) {
            bool isSwL = true;
            for(int j = 1; j <= lb; j++) {
               if(iLow(m_symbol, m_biasTF, i - j) <= lo ||
                  iLow(m_symbol, m_biasTF, i + j) <= lo) {
                  isSwL = false; break;
               }
            }
            if(isSwL) sl[slC++] = lo;
         }
      }

      if(shC >= 2 && slC >= 2) {
         if(sh[0] > sh[1] && sl[0] > sl[1]) return BIAS_BULLISH;
         if(sh[0] < sh[1] && sl[0] < sl[1]) return BIAS_BEARISH;
      }

      double c1 = iClose(m_symbol, m_biasTF, 1);
      double ema[];
      ArraySetAsSeries(ema, true);
      int emaH = iMA(m_symbol, m_biasTF, 50, 0, MODE_EMA, PRICE_CLOSE);
      if(emaH != INVALID_HANDLE) {
         int copied = CopyBuffer(emaH, 0, 0, 3, ema);
         IndicatorRelease(emaH);
         if(copied >= 3) {
            bool rising  = (ema[0] > ema[1] && ema[1] > ema[2]);
            bool falling = (ema[0] < ema[1] && ema[1] < ema[2]);
            if(c1 > ema[1] && rising)  return BIAS_BULLISH;
            if(c1 < ema[1] && falling) return BIAS_BEARISH;
         }
      }
      return BIAS_NONE;
   }

   //==========================================================
   // M15 BIAS -- swing structure analysis
   //==========================================================
   ENUM_HTF_BIAS GetM15Bias() {
      int lb = 2;
      int maxBars = MathMin(iBars(m_symbol, m_htf) - lb - 1, 40);
      if(maxBars < lb + 3) return BIAS_NONE;

      double sh[];
      double sl[];
      ArrayResize(sh, 2);
      ArrayResize(sl, 2);
      int shC = 0, slC = 0;

      for(int i = lb; i < maxBars && (shC < 2 || slC < 2); i++) {
         double hi = iHigh(m_symbol, m_htf, i);
         if(shC < 2) {
            bool isSwH = true;
            for(int j = 1; j <= lb; j++) {
               if(iHigh(m_symbol, m_htf, i - j) >= hi ||
                  iHigh(m_symbol, m_htf, i + j) >= hi) {
                  isSwH = false; break;
               }
            }
            if(isSwH) sh[shC++] = hi;
         }

         double lo = iLow(m_symbol, m_htf, i);
         if(slC < 2) {
            bool isSwL = true;
            for(int j = 1; j <= lb; j++) {
               if(iLow(m_symbol, m_htf, i - j) <= lo ||
                  iLow(m_symbol, m_htf, i + j) <= lo) {
                  isSwL = false; break;
               }
            }
            if(isSwL) sl[slC++] = lo;
         }
      }

      if(shC >= 2 && slC >= 2) {
         if(sh[0] > sh[1] && sl[0] > sl[1]) return BIAS_BULLISH;
         if(sh[0] < sh[1] && sl[0] < sl[1]) return BIAS_BEARISH;
      }
      return BIAS_NONE;
   }

   //==========================================================
   // M5 SWING STRUCTURE
   //==========================================================
   void UpdateSwingStructure() {
      datetime currentBar = iTime(m_symbol, m_tf, 0);
      if(currentBar == m_lastSwingUpdate) return;
      m_lastSwingUpdate = currentBar;

      int lb = SWING_LOOKBACK;
      int totalBars = iBars(m_symbol, m_tf);
      int scanBars = MathMin(totalBars - 1, 100);

      m_shCount = 0;
      m_slCount = 0;
      ArrayResize(m_swingHighs, MAX_SWING_POINTS);
      ArrayResize(m_swingLows,  MAX_SWING_POINTS);

      double minRange = m_isGold ? PipsToPrice(MIN_SWING_RANGE_GOLD)
                                 : PipsToPrice(MIN_SWING_RANGE_FX);

      for(int i = lb; i < scanBars - lb; i++) {
         if(m_shCount >= MAX_SWING_POINTS && m_slCount >= MAX_SWING_POINTS)
            break;

         double hi = iHigh(m_symbol, m_tf, i);
         double lo = iLow(m_symbol,  m_tf, i);

         if(m_shCount < MAX_SWING_POINTS) {
            bool isSwingHi = true;
            for(int j = 1; j <= lb; j++) {
               if(iHigh(m_symbol, m_tf, i - j) >= hi ||
                  iHigh(m_symbol, m_tf, i + j) >= hi) {
                  isSwingHi = false; break;
               }
            }
            if(isSwingHi) {
               double localLow = lo;
               for(int j = 1; j <= lb; j++) {
                  double ll = iLow(m_symbol, m_tf, i + j);
                  if(ll < localLow) localLow = ll;
               }
               if((hi - localLow) >= minRange) {
                  m_swingHighs[m_shCount].price    = hi;
                  m_swingHighs[m_shCount].time     = iTime(m_symbol, m_tf, i);
                  m_swingHighs[m_shCount].barIndex = i;
                  m_swingHighs[m_shCount].isHigh   = true;
                  m_swingHighs[m_shCount].swept    = false;
                  m_shCount++;
               }
            }
         }

         if(m_slCount < MAX_SWING_POINTS) {
            bool isSwingLo = true;
            for(int j = 1; j <= lb; j++) {
               if(iLow(m_symbol, m_tf, i - j) <= lo ||
                  iLow(m_symbol, m_tf, i + j) <= lo) {
                  isSwingLo = false; break;
               }
            }
            if(isSwingLo) {
               double localHigh = hi;
               for(int j = 1; j <= lb; j++) {
                  double hh = iHigh(m_symbol, m_tf, i + j);
                  if(hh > localHigh) localHigh = hh;
               }
               if((localHigh - lo) >= minRange) {
                  m_swingLows[m_slCount].price    = lo;
                  m_swingLows[m_slCount].time     = iTime(m_symbol, m_tf, i);
                  m_swingLows[m_slCount].barIndex = i;
                  m_swingLows[m_slCount].isHigh   = false;
                  m_swingLows[m_slCount].swept    = false;
                  m_slCount++;
               }
            }
         }
      }
   }

   //==========================================================
   // CHECK SWING SWEEP
   //==========================================================
   bool CheckSwingSweep(ENUM_SIGNAL_DIRECTION &sweepDir,
                        double &sweepWick, datetime &sweepTime) {
      double sweepMin, sweepMax;
      if(m_isGold)     { sweepMin = PipsToPrice(SWEEP_MIN_PIPS_GOLD); sweepMax = PipsToPrice(SWEEP_MAX_PIPS_GOLD); }
      else if(m_isJPY) { sweepMin = PipsToPrice(SWEEP_MIN_PIPS_JPY);  sweepMax = PipsToPrice(SWEEP_MAX_PIPS_JPY);  }
      else             { sweepMin = PipsToPrice(SWEEP_MIN_PIPS_FX);    sweepMax = PipsToPrice(SWEEP_MAX_PIPS_FX);   }

      int barsToCheck = MathMin(3, iBars(m_symbol, m_tf) - 1);
      int minSwingAge = SWING_LOOKBACK * 2;

      for(int i = 1; i <= barsToCheck; i++) {
         double hi = iHigh(m_symbol,  m_tf, i);
         double lo = iLow(m_symbol,   m_tf, i);
         double cl = iClose(m_symbol, m_tf, i);

         for(int s = 0; s < m_shCount; s++) {
            if(m_swingHighs[s].swept) continue;
            if(m_swingHighs[s].barIndex <= i + 1) continue;
            if(m_swingHighs[s].barIndex - i < minSwingAge) continue;
            double pierce = hi - m_swingHighs[s].price;
            if(pierce >= sweepMin && pierce <= sweepMax && cl <= m_swingHighs[s].price) {
               m_swingHighs[s].swept = true;
               sweepDir  = SIGNAL_SELL;
               sweepWick = hi;
               sweepTime = iTime(m_symbol, m_tf, i);
               return true;
            }
         }

         for(int s = 0; s < m_slCount; s++) {
            if(m_swingLows[s].swept) continue;
            if(m_swingLows[s].barIndex <= i + 1) continue;
            if(m_swingLows[s].barIndex - i < minSwingAge) continue;
            double pierce = m_swingLows[s].price - lo;
            if(pierce >= sweepMin && pierce <= sweepMax && cl >= m_swingLows[s].price) {
               m_swingLows[s].swept = true;
               sweepDir  = SIGNAL_BUY;
               sweepWick = lo;
               sweepTime = iTime(m_symbol, m_tf, i);
               return true;
            }
         }
      }
      return false;
   }

   //==========================================================
   // ASIA MAPPING WITH RANGE FILTER
   //==========================================================
   void MapAsiaLevels() {
      datetime today = GetGMTDate();
      if(m_asia.valid && m_asia.date == today) return;

      m_asia.high = -1; m_asia.low = -1;
      m_asia.valid = false; m_asia.highSwept = false; m_asia.lowSwept = false;
      m_asia.date = today;

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
         if(barDate != today) { if(counted > 0) break; continue; }

         if(gmtH >= ASIA_H_START && gmtH < ASIA_H_END) {
            double h = iHigh(m_symbol, m_tf, i);
            double l = iLow(m_symbol,  m_tf, i);
            if(m_asia.high < 0 || h > m_asia.high) { m_asia.high = h; m_asia.highTime = barTime; }
            if(m_asia.low  < 0 || l < m_asia.low)  { m_asia.low  = l; m_asia.lowTime  = barTime; }
            counted++;
         }
      }

      if(counted >= 3 && m_asia.high > 0 && m_asia.low > 0 && m_asia.high > m_asia.low) {
         double rangePips = PriceToPips(m_asia.high - m_asia.low);
         double minRange = m_isGold ? MIN_ASIA_RANGE_GOLD : MIN_ASIA_RANGE_FX;
         double maxRange = m_isGold ? MAX_ASIA_RANGE_GOLD : MAX_ASIA_RANGE_FX;

         if(rangePips < minRange) {
            Print("[", m_symbol, "] Asia range too small: ",
                  DoubleToString(rangePips, 1), "p (min ", DoubleToString(minRange, 0), ")");
            return;
         }
         if(rangePips > maxRange) {
            Print("[", m_symbol, "] Asia range too large: ",
                  DoubleToString(rangePips, 1), "p (max ", DoubleToString(maxRange, 0), ")");
            return;
         }

         m_asia.valid = true;
         Print("[", m_symbol, "] Asia: Hi=", DoubleToString(m_asia.high, 2),
               " Lo=", DoubleToString(m_asia.low, 2),
               " Range=", DoubleToString(rangePips, 1), "p");
      }
   }

   bool CheckAsiaSweep(ENUM_SIGNAL_DIRECTION &sweepDir,
                       double &sweepWick, datetime &sweepTime) {
      if(!m_asia.valid) return false;
      double sweepMin, sweepMax;
      if(m_isGold)     { sweepMin = PipsToPrice(SWEEP_MIN_PIPS_GOLD); sweepMax = PipsToPrice(SWEEP_MAX_PIPS_GOLD); }
      else if(m_isJPY) { sweepMin = PipsToPrice(SWEEP_MIN_PIPS_JPY);  sweepMax = PipsToPrice(SWEEP_MAX_PIPS_JPY);  }
      else             { sweepMin = PipsToPrice(SWEEP_MIN_PIPS_FX);    sweepMax = PipsToPrice(SWEEP_MAX_PIPS_FX);   }

      int barsToCheck = MathMin(5, iBars(m_symbol, m_tf) - 1);
      for(int i = 1; i <= barsToCheck; i++) {
         double hi = iHigh(m_symbol,  m_tf, i);
         double lo = iLow(m_symbol,   m_tf, i);
         double cl = iClose(m_symbol, m_tf, i);

         if(!m_asia.highSwept) {
            double pierce = hi - m_asia.high;
            if(pierce >= sweepMin && pierce <= sweepMax && cl <= m_asia.high) {
               m_asia.highSwept = true;
               sweepDir = SIGNAL_SELL; sweepWick = hi; sweepTime = iTime(m_symbol, m_tf, i);
               Print("[", m_symbol, "] ASIA HI SWEEP bar[", IntegerToString(i),
                     "] pierce=", DoubleToString(PriceToPips(pierce), 1), "p");
               return true;
            }
         }
         if(!m_asia.lowSwept) {
            double pierce = m_asia.low - lo;
            if(pierce >= sweepMin && pierce <= sweepMax && cl >= m_asia.low) {
               m_asia.lowSwept = true;
               sweepDir = SIGNAL_BUY; sweepWick = lo; sweepTime = iTime(m_symbol, m_tf, i);
               Print("[", m_symbol, "] ASIA LO SWEEP bar[", IntegerToString(i),
                     "] pierce=", DoubleToString(PriceToPips(pierce), 1), "p");
               return true;
            }
         }
      }
      return false;
   }

   //==========================================================
   // SPREAD CHECK
   //==========================================================
   bool SpreadOK() {
      double sp = (double)SymbolInfoInteger(m_symbol, SYMBOL_SPREAD)
                  * SymbolInfoDouble(m_symbol, SYMBOL_POINT);
      double spPips = PriceToPips(sp);
      double maxP;
      if(m_isGold) maxP = MAX_SPREAD_PIPS_GOLD;
      else if(m_isBTC) maxP = MAX_SPREAD_PIPS_BTC;
      else maxP = MAX_SPREAD_PIPS_FX;
      return (spPips <= maxP);
   }

   //==========================================================
   // FIND STRUCTURE LEVEL FOR CHoCH
   // After a low sweep (BUY), finds the nearest high to break above
   // After a high sweep (SELL), finds the nearest low to break below
   //==========================================================
   bool FindStructureLevel(ENUM_SIGNAL_DIRECTION dir, datetime sweepTime, double &level) {
      int sweepIdx = -1;
      for(int i = 1; i < 25; i++) {
         datetime bt = iTime(m_symbol, m_tf, i);
         if(bt <= sweepTime) { sweepIdx = i; break; }
      }
      if(sweepIdx < 1) return false;

      int end = MathMin(sweepIdx + 6, iBars(m_symbol, m_tf) - 1);

      if(dir == SIGNAL_BUY) {
         double best = 0;
         for(int i = sweepIdx; i <= end; i++) {
            double h = iHigh(m_symbol, m_tf, i);
            if(h > best) best = h;
         }
         level = best;
         return (best > 0);
      } else {
         double best = DBL_MAX;
         for(int i = sweepIdx; i <= end; i++) {
            double l = iLow(m_symbol, m_tf, i);
            if(l < best) best = l;
         }
         level = best;
         return (best < DBL_MAX);
      }
   }

   //==========================================================
   // FVG DETECTION WITH CHoCH REQUIREMENT
   // The displacement candle must:
   //   1. Have body >= DISP_ATR_MULT * ATR (strong displacement)
   //   2. Close beyond the structure level (CHoCH confirmed)
   //   3. Create a true FVG or serve as the basis for a proper OB
   // Search from sweep time forward (closest FVG = best entry)
   //==========================================================
   bool DetectFVGWithCHoCH(ENUM_SIGNAL_DIRECTION dir, datetime sweepTime,
                            double structureLevel, SFVG &fvg) {
      double atr = GetATR(m_tf, 14);
      if(atr <= 0) return false;
      double minBody = atr * DISP_ATR_MULT;
      int maxBars = MathMin(iBars(m_symbol, m_tf) - 2, 20);

      for(int i = maxBars - 1; i >= 2; i--) {
         datetime barT = iTime(m_symbol, m_tf, i);
         if(barT <= sweepTime) continue;

         double op = iOpen(m_symbol,  m_tf, i);
         double hi = iHigh(m_symbol,  m_tf, i);
         double lo = iLow(m_symbol,   m_tf, i);
         double cl = iClose(m_symbol, m_tf, i);
         double body = MathAbs(cl - op);

         if(dir == SIGNAL_BUY) {
            if(cl <= op || body < minBody) continue;
            if(cl <= structureLevel) continue;

            if(i + 1 < maxBars) {
               double prevH = iHigh(m_symbol, m_tf, i + 1);
               double nextL = iLow(m_symbol,  m_tf, i - 1);
               if(prevH < nextL) {
                  fvg.isBullish = true;
                  fvg.lower = prevH;
                  fvg.upper = nextL;
                  fvg.midpoint = (prevH + nextL) / 2.0;
                  fvg.time = barT;
                  fvg.active = true;
                  Print("[", m_symbol, "] BUY FVG found: ",
                        DoubleToString(fvg.lower, 5), "-", DoubleToString(fvg.upper, 5),
                        " CHoCH above ", DoubleToString(structureLevel, 5));
                  return true;
               }
            }

            if(i + 1 < maxBars) {
               double obO = iOpen(m_symbol,  m_tf, i + 1);
               double obC = iClose(m_symbol, m_tf, i + 1);
               double obBody = MathAbs(obO - obC);
               if(obC < obO && obBody > atr * 0.15) {
                  fvg.isBullish = true;
                  fvg.lower = obC;
                  fvg.upper = obO;
                  fvg.midpoint = (obC + obO) / 2.0;
                  fvg.time = iTime(m_symbol, m_tf, i + 1);
                  fvg.active = true;
                  Print("[", m_symbol, "] BUY OB found: ",
                        DoubleToString(fvg.lower, 5), "-", DoubleToString(fvg.upper, 5),
                        " CHoCH above ", DoubleToString(structureLevel, 5));
                  return true;
               }
            }
         }

         if(dir == SIGNAL_SELL) {
            if(cl >= op || body < minBody) continue;
            if(cl >= structureLevel) continue;

            if(i + 1 < maxBars) {
               double prevL = iLow(m_symbol,  m_tf, i + 1);
               double nextH = iHigh(m_symbol, m_tf, i - 1);
               if(prevL > nextH) {
                  fvg.isBullish = false;
                  fvg.upper = prevL;
                  fvg.lower = nextH;
                  fvg.midpoint = (prevL + nextH) / 2.0;
                  fvg.time = barT;
                  fvg.active = true;
                  Print("[", m_symbol, "] SELL FVG found: ",
                        DoubleToString(fvg.lower, 5), "-", DoubleToString(fvg.upper, 5),
                        " CHoCH below ", DoubleToString(structureLevel, 5));
                  return true;
               }
            }

            if(i + 1 < maxBars) {
               double obO = iOpen(m_symbol,  m_tf, i + 1);
               double obC = iClose(m_symbol, m_tf, i + 1);
               double obBody = MathAbs(obO - obC);
               if(obC > obO && obBody > atr * 0.15) {
                  fvg.isBullish = false;
                  fvg.lower = obO;
                  fvg.upper = obC;
                  fvg.midpoint = (obO + obC) / 2.0;
                  fvg.time = iTime(m_symbol, m_tf, i + 1);
                  fvg.active = true;
                  Print("[", m_symbol, "] SELL OB found: ",
                        DoubleToString(fvg.lower, 5), "-", DoubleToString(fvg.upper, 5),
                        " CHoCH below ", DoubleToString(structureLevel, 5));
                  return true;
               }
            }
         }
      }
      return false;
   }

   //==========================================================
   // LIQUIDITY TARGET
   //==========================================================
   double FindLiquidityTarget(ENUM_SIGNAL_DIRECTION dir, double entry, double minDist) {
      int scan = MathMin(100, iBars(m_symbol, m_htf) - 1);
      if(dir == SIGNAL_BUY) {
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

   //==========================================================
   // BUILD SETUP
   //==========================================================
   bool BuildSetup(ENUM_SIGNAL_DIRECTION dir, SFVG &fvg,
                   double sweepWick, ENUM_SESSION session,
                   ENUM_SETUP_TYPE sType) {
      int digits = (int)SymbolInfoInteger(m_symbol, SYMBOL_DIGITS);
      double entry = NormalizeDouble(fvg.midpoint, digits);
      double sl;

      double buffer = m_isGold ? PipsToPrice(SL_BUFFER_PIPS_GOLD)
                               : PipsToPrice(SL_BUFFER_PIPS_FX);

      if(dir == SIGNAL_BUY) {
         sl = NormalizeDouble(sweepWick - buffer, digits);
         if(entry <= sl) return false;
      } else {
         sl = NormalizeDouble(sweepWick + buffer, digits);
         if(entry >= sl) return false;
      }

      double slDist = MathAbs(entry - sl);
      double slPips = PriceToPips(slDist);

      double maxSL;
      if(m_isGold) maxSL = MAX_SL_PIPS_GOLD;
      else if(m_isBTC) maxSL = MAX_SL_PIPS_BTC;
      else if(m_isJPY) maxSL = MAX_SL_PIPS_JPY;
      else maxSL = MAX_SL_PIPS_FOREX;

      double minSL = m_isGold ? MIN_SL_PIPS_GOLD : MIN_SL_PIPS_FX;

      if(slPips > maxSL) {
         Print("[", m_symbol, "] SL too wide: ", DoubleToString(slPips, 1),
               "p > ", DoubleToString(maxSL, 0));
         return false;
      }
      if(slPips < minSL) {
         Print("[", m_symbol, "] SL too tight: ", DoubleToString(slPips, 1),
               "p < ", DoubleToString(minSL, 1));
         return false;
      }

      double minTPDist = slDist * TARGET_RR;
      double liq = FindLiquidityTarget(dir, entry, minTPDist);
      double tp;

      if(dir == SIGNAL_BUY)
         tp = NormalizeDouble(((liq - entry) >= minTPDist) ? liq : entry + minTPDist, digits);
      else
         tp = NormalizeDouble(((entry - liq) >= minTPDist) ? liq : entry - minTPDist, digits);

      double actualRR = MathAbs(tp - entry) / slDist;

      m_setup.direction    = dir;
      m_setup.entryPrice   = entry;
      m_setup.stopLoss     = sl;
      m_setup.takeProfit   = tp;
      m_setup.riskReward   = actualRR;
      m_setup.slPips       = slPips;
      m_setup.fvg          = fvg;
      m_setup.fvgFound     = true;
      m_setup.chochDone    = true;
      m_setup.session      = session;
      m_setup.setupType    = sType;
      m_setup.setupTime    = TimeCurrent();
      m_setup.phase        = PHASE_CONFIRMED;
      m_setup.sweepWickTip = sweepWick;

      string sTypeStr = (sType == SETUP_ASIA_SWEEP) ? "Asia" : "Swing";
      string dirStr   = (dir == SIGNAL_BUY) ? "BUY" : "SELL";
      m_setup.reason = sTypeStr + " " + dirStr + " SL="
                     + DoubleToString(slPips, 1) + "p RR=1:"
                     + DoubleToString(actualRR, 1);

      Print("[", m_symbol, "] === ", sTypeStr, " SETUP (CHoCH confirmed) ===");
      Print("[", m_symbol, "] ", dirStr,
            " E=", DoubleToString(entry, digits),
            " SL=", DoubleToString(sl, digits),
            " TP=", DoubleToString(tp, digits),
            " ", DoubleToString(slPips, 1), "p 1:",
            DoubleToString(actualRR, 1));
      return true;
   }

   //==========================================================
   // TRY BUILD FROM SWEEP (sweep + CHoCH + FVG + setup)
   //==========================================================
   bool TryBuildFromSweep(ENUM_SIGNAL_DIRECTION dir, double sweepWick,
                          datetime sweepTime, ENUM_SESSION session,
                          ENUM_SETUP_TYPE sType) {
      double structureLevel;
      if(!FindStructureLevel(dir, sweepTime, structureLevel))
         return false;

      SFVG fvg;
      ZeroMemory(fvg);
      if(!DetectFVGWithCHoCH(dir, sweepTime, structureLevel, fvg))
         return false;

      return BuildSetup(dir, fvg, sweepWick, session, sType);
   }

public:
   CSilverBullet(string symbol, ENUM_TIMEFRAMES tf, ENUM_TIMEFRAMES htf) {
      m_symbol = symbol; m_tf = tf; m_htf = htf;
      m_biasTF = PERIOD_H1;

      m_isGold = (StringFind(symbol, "XAU") >= 0 || StringFind(symbol, "GOLD") >= 0);
      m_isJPY  = (StringFind(symbol, "JPY") >= 0);
      m_isBTC  = (StringFind(symbol, "BTC") >= 0);

      if(m_isGold)     m_pipSize = 0.10;
      else if(m_isJPY) m_pipSize = 0.01;
      else if(m_isBTC) m_pipSize = 1.0;
      else             m_pipSize = 0.0001;

      m_gmtOffsetSec = DetectGMTOffset();
      ZeroMemory(m_asia); ZeroMemory(m_setup);
      m_setup.phase = PHASE_IDLE;
      m_shCount = 0; m_slCount = 0;
      m_lastSwingUpdate = 0; m_lastTradeBar = 0;

      ArrayResize(m_swingHighs, MAX_SWING_POINTS);
      ArrayResize(m_swingLows,  MAX_SWING_POINTS);

      Print("[", symbol, "] v7 engine init pip=", DoubleToString(m_pipSize, 5),
            " gmt=", IntegerToString(m_gmtOffsetSec / 3600), "h");
   }

   //==========================================================
   // MAIN UPDATE
   //==========================================================
   bool Update() {
      ENUM_SESSION session = GetCurrentSession();

      if(session == SESSION_ASIA) {
         MapAsiaLevels();
         UpdateSwingStructure();
         if(m_setup.phase == PHASE_IDLE) m_setup.phase = PHASE_WATCHING;
         return false;
      }

      if(session != SESSION_LONDON_KILL && session != SESSION_NY_KILL) {
         UpdateSwingStructure();
         return false;
      }

      if(m_setup.phase == PHASE_CONFIRMED)
         return true;

      UpdateSwingStructure();
      if(!m_asia.valid) MapAsiaLevels();
      if(!SpreadOK()) return false;

      datetime currentBar = iTime(m_symbol, m_tf, 0);
      if(m_lastTradeBar > 0) {
         int barsSince = (int)((currentBar - m_lastTradeBar) / PeriodSeconds(m_tf));
         if(barsSince < MIN_BARS_BETWEEN_TRADES) return false;
      }

      // Pending swept phase: keep looking for CHoCH+FVG
      if(m_setup.phase == PHASE_SWEPT) {
         datetime refTime = (m_asia.sweepTime > 0) ? m_asia.sweepTime : iTime(m_symbol, m_tf, 15);
         double wick = m_setup.sweepWickTip;
         ENUM_SETUP_TYPE st = m_setup.setupType;

         if(TryBuildFromSweep(m_setup.direction, wick, refTime, session, st))
            return true;

         int barsSinceSweep = 0;
         if(m_asia.sweepTime > 0)
            barsSinceSweep = (int)((TimeCurrent() - m_asia.sweepTime) / PeriodSeconds(m_tf));
         if(barsSinceSweep > MAX_BARS_AFTER_SWEEP) {
            m_setup.phase = PHASE_WATCHING;
            if(m_setup.direction == SIGNAL_BUY)  m_asia.lowSwept  = false;
            if(m_setup.direction == SIGNAL_SELL) m_asia.highSwept = false;
         }
         return false;
      }

      // =====================================================
      // MODE 1: Asia level sweep
      // REQUIRES H1 OR M15 bias alignment
      // =====================================================
      ENUM_SIGNAL_DIRECTION asiaDir = SIGNAL_NONE;
      double asiaWick = 0; datetime asiaSweepT = 0;
      if(CheckAsiaSweep(asiaDir, asiaWick, asiaSweepT)) {
         ENUM_HTF_BIAS h1bias  = GetH1Bias();
         ENUM_HTF_BIAS m15bias = GetM15Bias();

         bool h1Match  = (asiaDir == SIGNAL_BUY && h1bias  == BIAS_BULLISH) ||
                         (asiaDir == SIGNAL_SELL && h1bias  == BIAS_BEARISH);
         bool m15Match = (asiaDir == SIGNAL_BUY && m15bias == BIAS_BULLISH) ||
                         (asiaDir == SIGNAL_SELL && m15bias == BIAS_BEARISH);

         if(!h1Match && !m15Match) {
            Print("[", m_symbol, "] Asia sweep SKIPPED: no bias alignment H1=",
                  (h1bias == BIAS_BULLISH ? "BULL" : (h1bias == BIAS_BEARISH ? "BEAR" : "NONE")),
                  " M15=",
                  (m15bias == BIAS_BULLISH ? "BULL" : (m15bias == BIAS_BEARISH ? "BEAR" : "NONE")));
            return false;
         }

         if(TryBuildFromSweep(asiaDir, asiaWick, asiaSweepT, session, SETUP_ASIA_SWEEP))
            return true;

         m_setup.direction    = asiaDir;
         m_setup.phase        = PHASE_SWEPT;
         m_setup.sweepWickTip = asiaWick;
         m_setup.setupType    = SETUP_ASIA_SWEEP;
         m_asia.sweepTime     = asiaSweepT;
         return false;
      }

      // =====================================================
      // MODE 2: Swing BOS
      // REQUIRES H1 OR M15 bias alignment
      // =====================================================
      ENUM_SIGNAL_DIRECTION swDir = SIGNAL_NONE;
      double swWick = 0; datetime swTime = 0;
      if(CheckSwingSweep(swDir, swWick, swTime)) {
         ENUM_HTF_BIAS h1bias  = GetH1Bias();
         ENUM_HTF_BIAS m15bias = GetM15Bias();

         bool h1Match  = (swDir == SIGNAL_BUY && h1bias  == BIAS_BULLISH) ||
                         (swDir == SIGNAL_SELL && h1bias  == BIAS_BEARISH);
         bool m15Match = (swDir == SIGNAL_BUY && m15bias == BIAS_BULLISH) ||
                         (swDir == SIGNAL_SELL && m15bias == BIAS_BEARISH);

         if(!h1Match && !m15Match) {
            Print("[", m_symbol, "] Swing BOS SKIPPED: no bias alignment H1=",
                  (h1bias == BIAS_BULLISH ? "BULL" : (h1bias == BIAS_BEARISH ? "BEAR" : "NONE")),
                  " M15=",
                  (m15bias == BIAS_BULLISH ? "BULL" : (m15bias == BIAS_BEARISH ? "BEAR" : "NONE")));
            return false;
         }

         if(TryBuildFromSweep(swDir, swWick, swTime, session, SETUP_SWING_BOS))
            return true;

         m_setup.direction    = swDir;
         m_setup.phase        = PHASE_SWEPT;
         m_setup.sweepWickTip = swWick;
         m_setup.setupType    = SETUP_SWING_BOS;
         m_asia.sweepTime     = swTime;
         return false;
      }

      return false;
   }

   SSetup       GetSetup()       { return m_setup; }
   SAsiaLevels  GetAsiaLevels()  { return m_asia; }
   bool         HasSetup()       { return (m_setup.phase == PHASE_CONFIRMED); }
   ENUM_SESSION GetSession()     { return GetCurrentSession(); }
   string       GetSessionName() {
      switch(GetCurrentSession()) {
         case SESSION_LONDON_KILL: return "London Killzone";
         case SESSION_NY_KILL:     return "NY Killzone";
         case SESSION_ASIA:        return "Asia (Mapping)";
         default:                  return "Off-Session";
      }
   }

   void OnTradePlaced() {
      m_setup.phase  = PHASE_IN_TRADE;
      m_lastTradeBar = iTime(m_symbol, m_tf, 0);
   }

   void OnTradeClose() {
      m_setup.phase = PHASE_WATCHING;
   }

   void ResetSession() {
      if(m_setup.phase != PHASE_IN_TRADE)
         m_setup.phase = PHASE_WATCHING;
      m_asia.highSwept = false;
      m_asia.lowSwept  = false;
      for(int i = 0; i < m_shCount; i++) m_swingHighs[i].swept = false;
      for(int i = 0; i < m_slCount; i++) m_swingLows[i].swept  = false;
   }

   void ResetDay() {
      ZeroMemory(m_asia); ZeroMemory(m_setup);
      m_setup.phase = PHASE_IDLE;
      m_shCount = 0; m_slCount = 0;
      m_lastSwingUpdate = 0; m_lastTradeBar = 0;
      m_gmtOffsetSec = DetectGMTOffset();
      Print("[", m_symbol, "] Day reset");
   }

   double GetCurrentATR() { return GetATR(m_tf, 14); }
};

#endif
