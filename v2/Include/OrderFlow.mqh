//+------------------------------------------------------------------+
//|                                                 OrderFlow.mqh    |
//|      Institutional EA v2 — Proxy Order Flow Analysis            |
//|  Uses tick volume + price action to detect institutional         |
//|  behavior: absorption, imbalance, stop hunts, delta divergence   |
//+------------------------------------------------------------------+
#ifndef ORDERFLOW_V2_MQH
#define ORDERFLOW_V2_MQH

#include "Defines.mqh"

class COrderFlow {
private:
   string m_symbol;
   bool   m_isGold;
   bool   m_isBTC;

   //-----------------------------------------------------------
   // WEIGHTED BAR DELTA
   // Bullish candle: all volume attributed to buys (+ delta)
   // Bearish candle: all volume attributed to sells (- delta)
   // Upper/lower wick fractions reduce the delta (partial fill)
   //-----------------------------------------------------------
   double BarDelta(ENUM_TIMEFRAMES tf, int shift) {
      double op = iOpen(m_symbol,  tf, shift);
      double hi = iHigh(m_symbol,  tf, shift);
      double lo = iLow(m_symbol,   tf, shift);
      double cl = iClose(m_symbol, tf, shift);
      double vol= (double)iTickVolume(m_symbol, tf, shift);
      double range = hi - lo;
      if(range <= 0 || vol <= 0) return 0;

      double body       = MathAbs(cl - op);
      double bodyFrac   = body / range;
      double net        = (cl >= op) ? 1.0 : -1.0;  // direction
      return net * bodyFrac * vol;
   }

public:
   COrderFlow(string symbol) {
      m_symbol = symbol;
      m_isGold = (StringFind(symbol, "XAU") >= 0 || StringFind(symbol, "GOLD") >= 0);
      m_isBTC  = (StringFind(symbol, "BTC") >= 0);
   }

   //-----------------------------------------------------------
   // CUMULATIVE DELTA over last N closed bars
   //-----------------------------------------------------------
   double GetCumulativeDelta(ENUM_TIMEFRAMES tf, int bars = 10) {
      double delta = 0;
      int avail = iBars(m_symbol, tf);
      int scan  = MathMin(bars, avail - 1);
      for(int i = 1; i <= scan; i++)
         delta += BarDelta(tf, i);
      return delta;
   }

   //-----------------------------------------------------------
   // ABSORPTION DETECTION
   // Price tests a level >= 3 times with increasing tick volume
   // but does NOT breach it → institutions absorbing sell/buy
   // level: the price level to test (e.g. a swing high/low)
   // dir:   DIR_BUY = level is a resistance (potential reversal down)
   //        DIR_SELL = level is a support (potential reversal up)
   //-----------------------------------------------------------
   bool DetectAbsorption(ENUM_TIMEFRAMES tf, double level,
                         ENUM_SIGNAL_DIR testDir, int lookback = 20) {
      if(level <= 0) return false;
      double pipSize = m_isGold ? 0.10 : (m_isBTC ? 1.0 : 0.0001);
      double zone    = pipSize * (m_isGold ? 5 : (m_isBTC ? 50 : 3)); // tolerance zone

      int touches   = 0;
      double prevVol = 0;
      bool   volIncreasing = false;
      int    avail  = iBars(m_symbol, tf);
      int    scan   = MathMin(lookback, avail - 1);

      for(int i = scan; i >= 1; i--) {
         double hi  = iHigh(m_symbol,  tf, i);
         double lo  = iLow(m_symbol,   tf, i);
         double cl  = iClose(m_symbol, tf, i);
         double vol = (double)iTickVolume(m_symbol, tf, i);

         bool touched = false;
         if(testDir == DIR_BUY) {
            // Testing a resistance: wick into it, close below
            touched = (hi >= level - zone && hi <= level + zone * 2 && cl < level);
         } else {
            // Testing a support: wick into it, close above
            touched = (lo <= level + zone && lo >= level - zone * 2 && cl > level);
         }

         if(touched) {
            touches++;
            if(prevVol > 0 && vol > prevVol * 1.15)
               volIncreasing = true;
            prevVol = vol;
         }
      }
      return (touches >= 3 && volIncreasing);
   }

   //-----------------------------------------------------------
   // VOLUME IMBALANCE DETECTION
   // Candle with tick volume > 1.8× 10-bar average + large body
   // = institutional entry signature
   //-----------------------------------------------------------
   bool DetectVolumeImbalance(ENUM_TIMEFRAMES tf, int shift = 1) {
      int avail = iBars(m_symbol, tf);
      if(avail < 15) return false;

      double vol = (double)iTickVolume(m_symbol, tf, shift);
      // average of preceding 10 bars (skip bar itself)
      double sum = 0;
      int    lookback = MathMin(10, avail - shift - 1);
      for(int i = shift + 1; i <= shift + lookback; i++)
         sum += (double)iTickVolume(m_symbol, tf, i);
      double avg = (lookback > 0) ? sum / lookback : vol;
      if(avg <= 0) return false;

      double op    = iOpen(m_symbol,  tf, shift);
      double cl    = iClose(m_symbol, tf, shift);
      double hi    = iHigh(m_symbol,  tf, shift);
      double lo    = iLow(m_symbol,   tf, shift);
      double body  = MathAbs(cl - op);
      double range = hi - lo;
      if(range <= 0) return false;

      bool largeBody = (body / range) >= 0.60;
      bool highVol   = (vol >= avg * 1.7);

      return (largeBody && highVol);
   }

   //-----------------------------------------------------------
   // STOP HUNT BAR DETECTION
   // Wick spikes beyond key level AND closes back inside range
   // = classic institutional stop-sweep reversal setup
   // Returns the direction of the REVERSAL (direction to trade)
   //-----------------------------------------------------------
   bool DetectStopHuntBar(ENUM_TIMEFRAMES tf, double keyLevel,
                          bool levelIsHigh, ENUM_SIGNAL_DIR &reverseDir,
                          int lookback = 5) {
      double pipSize = m_isGold ? 0.10 : (m_isBTC ? 1.0 : 0.0001);
      double minPierce = pipSize * (m_isGold ? 2 : (m_isBTC ? 30 : 1.5));
      double maxPierce = pipSize * (m_isGold ? 80 : (m_isBTC ? 500 : 12));
      int    avail  = iBars(m_symbol, tf);
      int    scan   = MathMin(lookback, avail - 1);

      for(int i = 1; i <= scan; i++) {
         double hi = iHigh(m_symbol,  tf, i);
         double lo = iLow(m_symbol,   tf, i);
         double cl = iClose(m_symbol, tf, i);

         if(levelIsHigh) {
            // Spike above → close back below → SELL reversal
            double pierce = hi - keyLevel;
            if(pierce >= minPierce && pierce <= maxPierce && cl <= keyLevel) {
               reverseDir = DIR_SELL;
               return true;
            }
         } else {
            // Spike below → close back above → BUY reversal
            double pierce = keyLevel - lo;
            if(pierce >= minPierce && pierce <= maxPierce && cl >= keyLevel) {
               reverseDir = DIR_BUY;
               return true;
            }
         }
      }
      return false;
   }

   //-----------------------------------------------------------
   // VOLUME DIVERGENCE
   // Price making new extreme but volume declining = momentum
   // exhaustion warning → favor reversal setups
   //-----------------------------------------------------------
   bool DetectVolumeDivergence(ENUM_TIMEFRAMES tf,
                                ENUM_SIGNAL_DIR priceDir,
                                int lookback = 15) {
      int avail = iBars(m_symbol, tf);
      int scan  = MathMin(lookback, avail - 2);

      double price1 = 0, price2 = 0;
      double vol1   = 0, vol2   = 0;

      if(priceDir == DIR_BUY) {
         // Find two swing highs — highest recent vs older
         for(int i = 2; i <= scan; i++) {
            double hi = iHigh(m_symbol, tf, i);
            double v  = (double)iTickVolume(m_symbol, tf, i);
            if(price1 == 0) { price1 = hi; vol1 = v; }
            else if(hi > price1) {
               price2 = price1; vol2 = vol1;
               price1 = hi;    vol1 = v;
            }
         }
         // New high + lower volume = bearish divergence
         return (price1 > price2 && price2 > 0 && vol1 < vol2 * 0.85);
      } else {
         // Find two swing lows
         double bigVal = DBL_MAX;
         for(int i = 2; i <= scan; i++) {
            double lo = iLow(m_symbol, tf, i);
            double v  = (double)iTickVolume(m_symbol, tf, i);
            if(price1 == bigVal || price1 == 0) { price1 = lo; vol1 = v; }
            else if(lo < price1) {
               price2 = price1; vol2 = vol1;
               price1 = lo;    vol1 = v;
            }
         }
         // New low + lower volume = bullish divergence
         return (price1 < price2 && price2 > 0 && vol1 < vol2 * 0.85);
      }
   }

   //-----------------------------------------------------------
   // COMPREHENSIVE SIGNAL SCAN
   // Returns a populated SOrderFlowData struct
   //-----------------------------------------------------------
   SOrderFlowData Scan(ENUM_TIMEFRAMES tf, double keyLevel = 0,
                       bool levelIsHigh = true, ENUM_SIGNAL_DIR sweepDir = DIR_NONE) {
      SOrderFlowData d;
      ZeroMemory(d);

      d.cumulativeDelta    = GetCumulativeDelta(tf, 10);
      d.dominantDelta      = GetCumulativeDelta(tf, 3);
      d.imbalanceDetected  = DetectVolumeImbalance(tf, 1);

      if(keyLevel > 0) {
         d.absorptionDetected = DetectAbsorption(tf, keyLevel, sweepDir, 20);
         ENUM_SIGNAL_DIR rd   = DIR_NONE;
         d.stopHuntBarDetected= DetectStopHuntBar(tf, keyLevel, levelIsHigh, rd, 5);
      }

      // Volume divergence: check if recent delta conflicts with price direction
      if(sweepDir == DIR_BUY)
         d.volumeDivergence = DetectVolumeDivergence(tf, DIR_SELL, 15); // divergence against prior downtrend
      else if(sweepDir == DIR_SELL)
         d.volumeDivergence = DetectVolumeDivergence(tf, DIR_BUY,  15);

      return d;
   }
};

#endif // ORDERFLOW_V2_MQH
