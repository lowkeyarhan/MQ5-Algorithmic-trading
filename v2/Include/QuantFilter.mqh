//+------------------------------------------------------------------+
//|                                               QuantFilter.mqh   |
//|      Institutional EA v2 — Quantitative Edge Filters            |
//|  Z-score, RSI divergence, confluence scoring, correlation       |
//+------------------------------------------------------------------+
#ifndef QUANTFILTER_V2_MQH
#define QUANTFILTER_V2_MQH

#include "Defines.mqh"
#include "MarketRegime.mqh"
#include "OrderFlow.mqh"
#include "LiquidityMap.mqh"

class CQuantFilter {
private:
   string m_symbol;
   bool   m_isGold;
   bool   m_isBTC;

   double GetATR(ENUM_TIMEFRAMES tf, int period = 14) {
      double buf[];
      ArraySetAsSeries(buf, true);
      int h = iATR(m_symbol, tf, period);
      if(h == INVALID_HANDLE) return 0;
      int c = CopyBuffer(h, 0, 1, 3, buf);
      IndicatorRelease(h);
      return (c >= 1) ? buf[0] : 0;
   }

public:
   CQuantFilter(string symbol) {
      m_symbol = symbol;
      m_isGold = (StringFind(symbol,"XAU") >= 0 || StringFind(symbol,"GOLD") >= 0);
      m_isBTC  = (StringFind(symbol,"BTC") >= 0);
   }

   //-----------------------------------------------------------
   // Z-SCORE of current close vs SMA
   // |Z| > 2.5 → overextended, skip momentum entries
   // |Z| < 1.0 → near mean, mean-reversion setups preferred
   //-----------------------------------------------------------
   double GetZScore(ENUM_TIMEFRAMES tf, int period = 20) {
      double close[];
      ArraySetAsSeries(close, true);
      int bars = iBars(m_symbol, tf);
      if(bars < period + 2) return 0;
      int c = CopyClose(m_symbol, tf, 1, period, close);
      if(c < period) return 0;

      double sum = 0;
      for(int i = 0; i < period; i++) sum += close[i];
      double mean = sum / period;

      double var = 0;
      for(int i = 0; i < period; i++) var += MathPow(close[i] - mean, 2);
      double stddev = MathSqrt(var / period);
      if(stddev <= 0) return 0;

      double curClose = iClose(m_symbol, tf, 1);
      return (curClose - mean) / stddev;
   }

   //-----------------------------------------------------------
   // RSI DIVERGENCE
   // Bearish: Price HH but RSI LH
   // Bullish: Price LL but RSI HL
   //-----------------------------------------------------------
   bool HasRSIDivergence(ENUM_TIMEFRAMES tf, ENUM_SIGNAL_DIR dir, int period = 14) {
      int bars = iBars(m_symbol, tf);
      if(bars < period + 20) return false;

      double rsi[];
      ArraySetAsSeries(rsi, true);
      int rsiH = iRSI(m_symbol, tf, period, PRICE_CLOSE);
      if(rsiH == INVALID_HANDLE) return false;
      int c = CopyBuffer(rsiH, 0, 1, 20, rsi);
      IndicatorRelease(rsiH);
      if(c < 15) return false;

      // Find two swing extremes in price and RSI
      if(dir == DIR_SELL) {
         // Look for Price making higher high, RSI making lower high (bearish divergence)
         double ph1 = 0, ph2 = 0;
         double rh1 = 0, rh2 = 0;
         int found = 0;
         for(int i = 2; i < 18 && found < 2; i++) {
            double hi  = iHigh(m_symbol, tf, i);
            double hP  = iHigh(m_symbol, tf, i+1);
            double hN  = iHigh(m_symbol, tf, i-1);
            if(hi > hP && hi >= hN) {
               found++;
               if(found == 1) { ph1 = hi; rh1 = rsi[i]; }
               else           { ph2 = hi; rh2 = rsi[i]; }
            }
         }
         // ph1 is more recent; bearish div: ph1 > ph2 (higher) but rh1 < rh2 (lower)
         return (found >= 2 && ph1 > ph2 && rh1 < rh2 * 0.97);
      } else {
         // Bullish divergence: Price LL but RSI HL
         double pl1 = DBL_MAX, pl2 = DBL_MAX;
         double rl1 = 0, rl2 = 0;
         int found = 0;
         for(int i = 2; i < 18 && found < 2; i++) {
            double lo = iLow(m_symbol, tf, i);
            double lP = iLow(m_symbol, tf, i+1);
            double lN = iLow(m_symbol, tf, i-1);
            if(lo < lP && lo <= lN) {
               found++;
               if(found == 1) { pl1 = lo; rl1 = rsi[i]; }
               else           { pl2 = lo; rl2 = rsi[i]; }
            }
         }
         return (found >= 2 && pl1 < pl2 && rl1 > rl2 * 1.03);
      }
   }

   //-----------------------------------------------------------
   // CONFLUENCE SCORE  (0–100)
   //
   // BASE LOGIC: SMC engine has already done strict filtering
   // (liquidity sweep + CHoCH + graded FVG required).
   // The score adds QUALITY BONUS on top of that base.
   //
   // Score breakdown:
   //  +20  SMC setup confirmed (base — always awarded here)
   //  +20  HTF Bias strong (3/3 TF agree) / +12 weak (2/3)
   //  +15  Regime TRENDING / +8 RANGING
   //  +15  Order Flow: stop hunt / +10 both signals / +6 one signal
   //  +10  Premium/Discount zone aligned
   //  +10  FVG Grade A / +5 Grade B
   //  +8   Liquidity pool proximity
   //  +5   RSI Divergence
   //  -15  Z-score overextension (|Z| > 2.5)
   //  -5   Z-score extended (|Z| > 2.0)
   //  Min to trade: 35/100
   //-----------------------------------------------------------
   int ScoreConfluence(
         const SConfluenceSetup &setup,
         const SMarketRegime    &regime,
         const SOrderFlowData   &of,
         int                     liquidityProximityBonus,
         bool                    inDiscount
   ) {
      // ── BASE: SMC setup confirmed ──────────────────────────
      int score = 20; // SMC engine: sweep + CHoCH + graded FVG = solid base

      // ── 1. HTF Bias (max 20) ──────────────────────────────
      if(regime.bias == BIAS_CONFLICT) {
         score -= 10; // conflicting signals — penalise but don't block
      } else if(regime.bias != BIAS_NONE) {
         bool aligned = (setup.direction == DIR_BUY  && regime.bias == BIAS_BULLISH) ||
                        (setup.direction == DIR_SELL && regime.bias == BIAS_BEARISH);
         if(aligned)
            score += regime.biasStrong ? 20 : 12;
         else
            score -= 15; // bias exists but against us — strong penalty
      }
      // BIAS_NONE: no bonus, no penalty — SMC setup alone can still trade

      // ── 2. Regime (max 15) ──────────────────────────────
      switch(regime.regime) {
         case REGIME_TRENDING_UP:
         case REGIME_TRENDING_DOWN: score += 15; break;
         case REGIME_RANGING:       score += 8;  break;
         case REGIME_CHOPPY:        score -= 10; break; // penalty not block
      }

      // ── 3. Order Flow (max 15) ──────────────────────────
      if(of.stopHuntBarDetected)                          score += 15;
      else if(of.absorptionDetected && of.imbalanceDetected) score += 10;
      else if(of.absorptionDetected || of.imbalanceDetected) score += 6;
      if(of.volumeDivergence)                             score += 4;

      // ── 4. Liquidity proximity (max 8) ──────────────────
      score += MathMin(liquidityProximityBonus, 8);

      // ── 5. Premium/Discount zone alignment (max 10) ─────
      bool zoneAligned = (setup.direction == DIR_BUY  && inDiscount) ||
                         (setup.direction == DIR_SELL && !inDiscount);
      if(zoneAligned) score += 10;

      // ── 6. FVG Grade (max 10) ───────────────────────────
      switch(setup.fvg.grade) {
         case FVG_A: score += 10; break;
         case FVG_B: score += 5;  break;
         case FVG_C: return 0;    // hard block — C-grade FVGs are garbage
         default:    break;
      }

      // ── 7. RSI Divergence bonus ──────────────────────────
      if(HasRSIDivergence(PERIOD_M15, setup.direction, 14)) score += 5;

      // ── 8. Z-score overextension penalty ────────────────
      double absZ = MathAbs(GetZScore(PERIOD_M15, 20));
      if(absZ > 2.5) score -= 15;
      else if(absZ > 2.0) score -= 5;

      return MathMax(0, MathMin(score, 100));
   }

   //-----------------------------------------------------------
   // CORRELATION BLOCK
   // Returns true if the new trade should be BLOCKED due to correlated exposure.
   // Positive correlation (same movement): EURUSD + GBPUSD
   // Inverse correlation: USDCHF vs EURUSD, USDJPY vs XAUUSD
   //-----------------------------------------------------------
   bool IsCorrelationBlocked(string newSym, ENUM_SIGNAL_DIR newDir,
                             string &openSymbols[], ENUM_SIGNAL_DIR &openDirs[],
                             int openCount) {
      for(int i = 0; i < openCount; i++) {
         string s          = openSymbols[i];
         ENUM_SIGNAL_DIR d = openDirs[i];
         if(d == DIR_NONE || newDir == DIR_NONE) continue;

         bool sameDir    = (d == newDir);
         bool inverseDir = (d != newDir);

         // Positive correlations: EURUSD <-> GBPUSD
         bool posCorr =
            ((StringFind(newSym,"EUR") >= 0) && (StringFind(s,"GBP") >= 0)) ||
            ((StringFind(newSym,"GBP") >= 0) && (StringFind(s,"EUR") >= 0));

         // Inverse correlations: EURUSD <-> USDCHF, XAUUSD <-> USDJPY
         bool invCorr =
            ((StringFind(newSym,"EUR") >= 0) && (StringFind(s,"CHF") >= 0)) ||
            ((StringFind(newSym,"CHF") >= 0) && (StringFind(s,"EUR") >= 0)) ||
            ((StringFind(newSym,"XAU") >= 0) && (StringFind(s,"JPY") >= 0)) ||
            ((StringFind(newSym,"JPY") >= 0) && (StringFind(s,"XAU") >= 0));

         if(posCorr && sameDir)    return true;
         if(invCorr && inverseDir) return true;
      }
      return false;
   }
};

#endif // QUANTFILTER_V2_MQH
