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

   double EMA(ENUM_TIMEFRAMES tf, int period, int shift = 1) {
      int h = iMA(m_symbol, tf, period, 0, MODE_EMA, PRICE_CLOSE);
      if(h == INVALID_HANDLE) return 0;
      double buf[];
      ArraySetAsSeries(buf, true);
      int c = CopyBuffer(h, 0, shift, 1, buf);
      IndicatorRelease(h);
      return (c >= 1) ? buf[0] : 0;
   }

   bool MomentumAligned(ENUM_SIGNAL_DIR dir) {
      // Entry-timeframe momentum: EMA20 over EMA50 + EMA20 slope.
      double e20m5_1 = EMA(PERIOD_M5, 20, 1);
      double e20m5_2 = EMA(PERIOD_M5, 20, 2);
      double e50m5_1 = EMA(PERIOD_M5, 50, 1);
      // Context-timeframe trend: EMA20 over EMA50 on M15.
      double e20m15  = EMA(PERIOD_M15, 20, 1);
      double e50m15  = EMA(PERIOD_M15, 50, 1);
      if(e20m5_1 <= 0 || e20m5_2 <= 0 || e50m5_1 <= 0 || e20m15 <= 0 || e50m15 <= 0)
         return false;

      bool bullM5  = (e20m5_1 > e50m5_1) && (e20m5_1 > e20m5_2);
      bool bearM5  = (e20m5_1 < e50m5_1) && (e20m5_1 < e20m5_2);
      bool bullM15 = (e20m15  > e50m15);
      bool bearM15 = (e20m15  < e50m15);

      if(dir == DIR_BUY)  return (bullM5 && bullM15);
      if(dir == DIR_SELL) return (bearM5 && bearM15);
      return false;
   }

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
   // PHILOSOPHY: Quality > Quantity. Fewer A+ setups beat
   // many B/C setups. The hard blocks below ensure we only
   // trade when we have a genuine institutional edge.
   //
   // Score breakdown:
   //  +20  SMC setup confirmed (base — always awarded)
   //  +20  HTF Bias strong aligned / +12 weak aligned
   //   0   HTF Bias NONE (neutral — allowed, no bonus)
   //  HARD BLOCK if bias is CONFLICT or OPPOSING direction
   //  +15  Regime TRENDING (required path to 55 min)
   //  HARD BLOCK if regime is RANGING with no aligned bias
   //  +15  Order Flow: stop hunt bar detected
   //  +10  Order Flow: absorption + imbalance together
   //  +6   Order Flow: one of absorption or imbalance
   //  +4   Volume divergence confirms reversal
   //  +10  FVG Grade A / +5 Grade B / BLOCK Grade C
   //  +10  Premium/Discount zone aligned with direction
   //  +8   Liquidity pool proximity (max)
   //  +5   RSI Divergence confirms reversal
   //  +10  Session sweep continuation (2nd+ setup in same direction)
   //  -10  Z-score overextension > 2.5 (entering too late)
   //  -5   Z-score extended > 2.0
   //  Min to trade: 55/100 — only A+ institutional setups
   //-----------------------------------------------------------
   int ScoreConfluence(
         const SConfluenceSetup &setup,
         const SMarketRegime    &regime,
         const SOrderFlowData   &of,
         int                     liquidityProximityBonus,
         bool                    inDiscount
   ) {
      // ── HARD BLOCKS — return 0 immediately if any fire ──

      // BLOCK 1: Never trade into conflicting bias (both TFs disagree on direction)
      if(regime.bias == BIAS_CONFLICT) return 0;

      // BLOCK 2: Never trade against HTF bias — this was the #1 cause of 39% win rate.
      // If we see a bullish sweep but H1+M15 are both bearish, institutions are selling.
      // We do NOT fade the institutional trend. Period.
      bool biasOpposing = (setup.direction == DIR_BUY  && regime.bias == BIAS_BEARISH) ||
                          (setup.direction == DIR_SELL && regime.bias == BIAS_BULLISH);
      if(biasOpposing) return 0;

      // BLOCK 3: No trade in ranging + unconfirmed market.
      // Ranging with BIAS_NONE = no directional edge at all.
      if(regime.regime == REGIME_RANGING && regime.bias == BIAS_NONE) return 0;

      // BLOCK 4: C-grade FVGs are noise — HARD BLOCK, never trade.
      // Removing this block was the primary cause of 20% win rate.
      if(setup.fvg.grade == FVG_C) return 0;

      // BLOCK 5: Require lower-timeframe momentum alignment.
      // This removes weak "technically aligned" setups that occur when M5 flow
      // is still against the intended direction (common source of stop-outs).
      if(!MomentumAligned(setup.direction)) return 0;

      // ── BASE SCORE ───────────────────────────────────────
      int score = 20; // SMC confirmed: liquidity sweep + real FVG detected

      // ── 1. HTF BIAS ALIGNMENT (max +20) ─────────────────
      // Reaching here means bias is either aligned or NONE.
      if(regime.bias != BIAS_NONE) {
         // bias is aligned (opposing was blocked above)
         score += regime.biasStrong ? 20 : 12;
      }
      // BIAS_NONE: no bonus — SMC alone can trade but needs strong order flow

      // ── 2. REGIME QUALITY (max +15) ──────────────────────
      // RANGING+aligned bias still gets a partial bonus (trend forming).
      switch(regime.regime) {
         case REGIME_TRENDING_UP:
         case REGIME_TRENDING_DOWN: score += 15; break;
         case REGIME_RANGING:       score += 5;  break; // reduced — less conviction
         case REGIME_CHOPPY:        return 0;            // hard block choppy
      }

      // ── 3. ORDER FLOW (max +19) ────────────────────
      // OF on M5 tick volume is unreliable — especially on Gold.
      // Use it as a SCORING BONUS, not a hard block.
      // Exception: when bias is NONE, OF is the ONLY edge — require it.
      bool hasOF = (of.stopHuntBarDetected || of.absorptionDetected ||
                    of.imbalanceDetected   || of.volumeDivergence);
      if(regime.bias == BIAS_NONE && !hasOF) return 0; // No bias + no OF = no edge

      if(of.stopHuntBarDetected)
         score += 15;                                // strongest signal
      else if(of.absorptionDetected && of.imbalanceDetected)
         score += 10;
      else if(of.absorptionDetected || of.imbalanceDetected)
         score += 6;

      if(of.volumeDivergence) score += 4;

      // ── 4. FVG GRADE (max +10) ───────────────────────────
      switch(setup.fvg.grade) {
         case FVG_A: score += 10; break;
         case FVG_B: score += 5;  break;
         default:    return 0;  // C-grade should never reach here (blocked above)
      }

      // ── 5. PREMIUM/DISCOUNT ZONE (max +10) ───────────────
      bool zoneAligned = (setup.direction == DIR_BUY  && inDiscount) ||
                         (setup.direction == DIR_SELL && !inDiscount);
      if(zoneAligned) score += 10;

      // ── 6. LIQUIDITY PROXIMITY (max +8) ──────────────────
      score += MathMin(liquidityProximityBonus, 8);

      // ── 7. RSI DIVERGENCE (max +5) ───────────────────────
      if(HasRSIDivergence(PERIOD_M15, setup.direction, 14)) score += 5;

      // ── 8. SESSION SWEEP CONTINUATION (max +10) ──────────
      // When the first sweep of the session has already established a direction,
      // a subsequent setup in the SAME direction is a trend-continuation trade —
      // the highest probability pattern in M5 SMC scalping. The first sweep tells
      // us where institutions are positioned; we should follow on every retracement FVG.
      bool isContinuation = (setup.sessionSweepDir != DIR_NONE &&
                             setup.direction == setup.sessionSweepDir);
      if(isContinuation) score += 10;

      // ── 9. Z-SCORE OVEREXTENSION PENALTY ─────────────────
      // Penalize but don't nuke — strong momentum has Z>2 naturally.
      double absZ = MathAbs(GetZScore(PERIOD_M15, 20));
      if(absZ > 2.5) score -= 10;
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
