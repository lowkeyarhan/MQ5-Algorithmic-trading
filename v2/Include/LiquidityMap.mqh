//+------------------------------------------------------------------+
//|                                               LiquidityMap.mqh  |
//|       Institutional EA v2 — Liquidity Pool Detection            |
//|  Maps equal highs/lows (stop clusters), swing pools, and        |
//|  premium/discount zones to find where price is likely to sweep  |
//+------------------------------------------------------------------+
#ifndef LIQUIDITYMAP_V2_MQH
#define LIQUIDITYMAP_V2_MQH

#include "Defines.mqh"

class CLiquidityMap {
private:
   string          m_symbol;
   bool            m_isGold;
   bool            m_isJPY;
   bool            m_isBTC;
   double          m_pipSize;

   SLiquidityPool  m_pools[];
   int             m_poolCount;

   double PipsToPrice(double pips) { return pips * m_pipSize; }

   //-----------------------------------------------------------
   // SCORE A LIQUIDITY POOL
   // touch count × freshness × proximity bonus
   //-----------------------------------------------------------
   double ScorePool(int touchCount, int ageInBars, double distPips) {
      double touchScore = MathMin(touchCount * 20.0, 60.0);
      double ageScore   = MathMax(0, 40.0 - ageInBars * 0.5);
      double proxScore  = MathMax(0, 20.0 - distPips * 0.5);
      return touchScore + ageScore + proxScore;
   }

public:
   CLiquidityMap(string symbol) {
      m_symbol  = symbol;
      m_isGold  = (StringFind(symbol, "XAU") >= 0 || StringFind(symbol, "GOLD") >= 0);
      m_isJPY   = (StringFind(symbol, "JPY") >= 0);
      m_isBTC   = (StringFind(symbol, "BTC") >= 0);

      if(m_isGold)      m_pipSize = 0.10;
      else if(m_isJPY)  m_pipSize = 0.01;
      else if(m_isBTC)  m_pipSize = 1.0;
      else              m_pipSize = 0.0001;

      m_poolCount = 0;
      ArrayResize(m_pools, 50);
   }

   //-----------------------------------------------------------
   // FIND EQUAL HIGHS (buy-stop clusters above price)
   // Groups highs within a tight pip tolerance → real cluster
   //-----------------------------------------------------------
   void FindEqualHighs(ENUM_TIMEFRAMES tf, int lookback = 80) {
      // Remove old buy-stop pools
      for(int i = 0; i < m_poolCount; i++) {
         if(m_pools[i].isBuyStop) { m_pools[i].active = false; }
      }

      double tol = PipsToPrice(m_isGold ? 8.0 : (m_isBTC ? 60.0 : 4.0));
      int    avail = iBars(m_symbol, tf);
      int    scan  = MathMin(lookback, avail - 2);
      double curP  = iClose(m_symbol, tf, 0);

      // Collect all swing highs
      double highs[]; datetime times[];
      int    cnt = 0;
      ArrayResize(highs, scan); ArrayResize(times, scan);

      for(int i = 1; i < scan; i++) {
         double hi   = iHigh(m_symbol, tf, i);
         double hiPrev= iHigh(m_symbol, tf, i+1);
         double hiNext= (i > 1) ? iHigh(m_symbol, tf, i-1) : hi;
         if(hi > hiPrev && hi >= hiNext) {
            highs[cnt] = hi;
            times[cnt] = iTime(m_symbol, tf, i);
            cnt++;
         }
      }

      // Find clusters
      bool used[];
      ArrayResize(used, cnt);
      ArrayInitialize(used, false);

      for(int i = 0; i < cnt; i++) {
         if(used[i]) continue;
         double clusterPrice = highs[i];
         int    touches = 1;
         datetime oldest = times[i];
         used[i] = true;

         for(int j = i+1; j < cnt; j++) {
            if(used[j]) continue;
            if(MathAbs(highs[j] - clusterPrice) <= tol) {
               touches++;
               clusterPrice = (clusterPrice + highs[j]) / 2.0; // refine cluster center
               used[j] = true;
               if(times[j] < oldest) oldest = times[j];
            }
         }

         if(touches >= 2 && clusterPrice > curP) {
            // Add pool — FIXED: resize only when array is full (>= not <)
            if(m_poolCount >= ArraySize(m_pools))
               ArrayResize(m_pools, m_poolCount + 10);
            double distPips = MathAbs(clusterPrice - curP) / m_pipSize;
            int age = (int)((TimeCurrent() - oldest) / PeriodSeconds(tf));

            m_pools[m_poolCount].price      = clusterPrice;
            m_pools[m_poolCount].isBuyStop  = true;
            m_pools[m_poolCount].touchCount = touches;
            m_pools[m_poolCount].ageInBars  = age;
            m_pools[m_poolCount].score      = ScorePool(touches, age, distPips);
            m_pools[m_poolCount].time       = oldest;
            m_pools[m_poolCount].active     = true;
            m_poolCount++;
         }
      }
   }

   //-----------------------------------------------------------
   // FIND EQUAL LOWS (sell-stop clusters below price)
   //-----------------------------------------------------------
   void FindEqualLows(ENUM_TIMEFRAMES tf, int lookback = 80) {
      for(int i = 0; i < m_poolCount; i++) {
         if(!m_pools[i].isBuyStop) m_pools[i].active = false;
      }

      double tol  = PipsToPrice(m_isGold ? 8.0 : (m_isBTC ? 60.0 : 4.0));
      int    avail = iBars(m_symbol, tf);
      int    scan  = MathMin(lookback, avail - 2);
      double curP  = iClose(m_symbol, tf, 0);

      double lows[]; datetime times[];
      int    cnt = 0;
      ArrayResize(lows, scan); ArrayResize(times, scan);

      for(int i = 1; i < scan; i++) {
         double lo    = iLow(m_symbol, tf, i);
         double loPrev= iLow(m_symbol, tf, i+1);
         double loNext= (i > 1) ? iLow(m_symbol, tf, i-1) : lo;
         if(lo < loPrev && lo <= loNext) {
            lows[cnt] = lo;
            times[cnt] = iTime(m_symbol, tf, i);
            cnt++;
         }
      }

      bool used[];
      ArrayResize(used, cnt);
      ArrayInitialize(used, false);

      for(int i = 0; i < cnt; i++) {
         if(used[i]) continue;
         double clusterPrice = lows[i];
         int    touches = 1;
         datetime oldest = times[i];
         used[i] = true;

         for(int j = i+1; j < cnt; j++) {
            if(used[j]) continue;
            if(MathAbs(lows[j] - clusterPrice) <= tol) {
               touches++;
               clusterPrice = (clusterPrice + lows[j]) / 2.0;
               used[j] = true;
               if(times[j] < oldest) oldest = times[j];
            }
         }

         if(touches >= 2 && clusterPrice < curP) {
            if(m_poolCount >= ArraySize(m_pools))
               ArrayResize(m_pools, m_poolCount + 10);
            double distPips = MathAbs(clusterPrice - curP) / m_pipSize;
            int age = (int)((TimeCurrent() - oldest) / PeriodSeconds(tf));

            m_pools[m_poolCount].price      = clusterPrice;
            m_pools[m_poolCount].isBuyStop  = false;
            m_pools[m_poolCount].touchCount = touches;
            m_pools[m_poolCount].ageInBars  = age;
            m_pools[m_poolCount].score      = ScorePool(touches, age, distPips);
            m_pools[m_poolCount].time       = oldest;
            m_pools[m_poolCount].active     = true;
            m_poolCount++;
         }
      }
   }

   //-----------------------------------------------------------
   // UPDATE FULL LIQUIDITY MAP (call once per new bar)
   //-----------------------------------------------------------
   void Update(ENUM_TIMEFRAMES tf = PERIOD_M15) {
      m_poolCount = 0;
      ArrayResize(m_pools, 50);
      FindEqualHighs(tf, 100);
      FindEqualLows(tf, 100);
   }

   //-----------------------------------------------------------
   // PREMIUM / DISCOUNT ZONE
   // Based on last major range (highest high & lowest low in N bars)
   // >50% = premium (institutional sell zone)
   // <50% = discount (institutional buy zone)
   //-----------------------------------------------------------
   bool IsInDiscount(ENUM_TIMEFRAMES tf = PERIOD_H1, int lookback = 60) {
      double curP = iClose(m_symbol, tf, 0);
      double hi   = -1, lo = DBL_MAX;
      int avail   = iBars(m_symbol, tf);
      int scan    = MathMin(lookback, avail - 1);
      for(int i = 1; i <= scan; i++) {
         double h = iHigh(m_symbol, tf, i);
         double l = iLow(m_symbol,  tf, i);
         if(h > hi) hi = h;
         if(l < lo) lo = l;
      }
      if(hi <= lo) return false;
      double eq = lo + (hi - lo) * 0.5;
      return (curP < eq);
   }

   bool IsInPremium(ENUM_TIMEFRAMES tf = PERIOD_H1, int lookback = 60) {
      return !IsInDiscount(tf, lookback);
   }

   //-----------------------------------------------------------
   // NEAREST POOL in a given direction
   // dir = DIR_BUY  → look for sell-stop pool above price (target)
   // dir = DIR_SELL → look for buy-stop pool below price (target)
   //-----------------------------------------------------------
   bool GetNearestPool(ENUM_SIGNAL_DIR dir, double curPrice,
                       SLiquidityPool &outPool) {
      double best = (dir == DIR_BUY) ? DBL_MAX : -1;
      int    bestIdx = -1;

      for(int i = 0; i < m_poolCount; i++) {
         if(!m_pools[i].active) continue;
         double p = m_pools[i].price;
         if(dir == DIR_BUY) {
            // Buy target = pool ABOVE price (sell-stop cluster)
            if(!m_pools[i].isBuyStop && p > curPrice && p < best) {
               best = p; bestIdx = i;
            }
         } else {
            // Sell target = pool BELOW price (buy-stop cluster)
            if(m_pools[i].isBuyStop && p < curPrice && p > best) {
               best = p; bestIdx = i;
            }
         }
      }
      if(bestIdx < 0) return false;
      outPool = m_pools[bestIdx];
      return true;
   }

   //-----------------------------------------------------------
   // CHECK IF ENTRY IS NEAR A POOL (confluence bonus)
   // Returns score bonus 0–15 based on proximity
   //-----------------------------------------------------------
   int ProximityBonus(double entryPrice, ENUM_SIGNAL_DIR dir, double maxPips = 10.0) {
      double maxDist = PipsToPrice(maxPips);
      for(int i = 0; i < m_poolCount; i++) {
         if(!m_pools[i].active) continue;
         double dist = MathAbs(m_pools[i].price - entryPrice);
         if(dist <= maxDist) {
            // Pool direction should push toward entry
            if((dir == DIR_BUY  && !m_pools[i].isBuyStop) ||
               (dir == DIR_SELL &&  m_pools[i].isBuyStop))
               continue; // wrong side
            double pipsDist = dist / m_pipSize;
            int bonus = (int)MathMax(0, 15.0 - pipsDist * 1.0);
            return bonus;
         }
      }
      return 0;
   }

   int GetPoolCount() { return m_poolCount; }
};

#endif // LIQUIDITYMAP_V2_MQH
