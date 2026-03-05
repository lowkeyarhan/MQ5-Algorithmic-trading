//+------------------------------------------------------------------+
//|                                               SilverBullet.mqh  |
//|         SMC Structure + Liquidity Sweep Scalp Engine v4.0       |
//|                                                                  |
//|  Step 1: Map Asia session High/Low as liquidity pools           |
//|  Step 2: Get H1 bias (bullish/bearish structure)                |
//|  Step 3: Detect sweep of Asia H/L during killzone               |
//|  Step 4: Confirm CHoCH via displacement candle                  |
//|  Step 5: Identify OB/FVG left by displacement                   |
//|  Step 6: Place LIMIT at OB/FVG. SL = structure. TP = 1:3 min   |
//+------------------------------------------------------------------+
#ifndef SILVERBULLET_MQH
#define SILVERBULLET_MQH

#include "Defines.mqh"

class CSilverBullet {
    private:
    string m_symbol;
    ENUM_TIMEFRAMES m_tf; // M5 entry
    ENUM_TIMEFRAMES m_htf; // M15 structure
    ENUM_TIMEFRAMES m_biasTF; // H1 bias

    SAsiaLevels m_asia;
    SSetup m_setup;
    bool m_isGold;
    bool m_isJPY;
    bool m_isBTC;
    double m_pipSize; // price distance of 1 pip

    int m_gmtOffsetSec; // broker server GMT offset in seconds

   //--- Convert pips to price distance for this symbol
    double PipsToPrice(double pips) {
        return pips * m_pipSize;
    }

    double PriceToPips(double priceDistance) {
        if(m_pipSize <= 0) return 0;
        return priceDistance / m_pipSize;
    }

   //--- Detect broker's GMT offset by comparing TimeGMT and TimeCurrent
    int DetectGMTOffset() {
        datetime gmt = TimeGMT();
        datetime server = TimeCurrent();
        return(int)(server - gmt);
    }

   //--- Convert server time to GMT
    datetime ServerToGMT(datetime serverTime) {
        return serverTime - m_gmtOffsetSec;
    }

   //--- Get GMT hour/minute from server time
    void ServerTimeToGMTComponents(datetime serverTime, int &hour, int &minute) {
        datetime gmt = ServerToGMT(serverTime);
        MqlDateTime dt;
        TimeToStruct(gmt, dt);
        hour = dt.hour;
        minute = dt.min;
    }

   //--- Get current GMT components
    void GetGMT(int &hour, int &minute) {
        MqlDateTime dt;
        TimeToStruct(TimeGMT(), dt);
        hour = dt.hour;
        minute = dt.min;
    }

   //--- Today's date in GMT
    datetime GetGMTDate() {
        MqlDateTime dt;
        TimeToStruct(TimeGMT(), dt);
        dt.hour = 0; dt.min = 0; dt.sec = 0;
        return StructToTime(dt);
    }

   //--- Which session are we in right now?
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

   //--- ATR (creates handle, reads, releases properly)
    double GetATR(ENUM_TIMEFRAMES tf, int period = 14) {
        double buf[];
        ArraySetAsSeries(buf, true);
        int h = iATR(m_symbol, tf, period);
        if(h == INVALID_HANDLE) return 0;
      // Need a few ticks for the indicator to calculate
        int copied = CopyBuffer(h, 0, 0, 3, buf);
        IndicatorRelease(h);
        if(copied < 2) return 0;
        return buf[1];
    }

   //--- H1 bias: determine if H1 structure is bullish or bearish
    ENUM_HTF_BIAS GetH1Bias() {
        double h1Close1 = iClose(m_symbol, m_biasTF, 1);
        double h1Close2 = iClose(m_symbol, m_biasTF, 2);
        double h1Close3 = iClose(m_symbol, m_biasTF, 3);
        double h1High1 = iHigh(m_symbol, m_biasTF, 1);
        double h1Low1 = iLow(m_symbol, m_biasTF, 1);
        double h1High2 = iHigh(m_symbol, m_biasTF, 2);
        double h1Low2 = iLow(m_symbol, m_biasTF, 2);

        if(h1Close1 <= 0 || h1Close2 <= 0) return BIAS_NONE;

      // Simple structure: higher highs + higher lows = bullish
        bool hh = (h1High1 > h1High2);
        bool hl = (h1Low1 > h1Low2);
        bool lh = (h1High1 < h1High2);
        bool ll = (h1Low1 < h1Low2);

      // Also check EMA trend on H1
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

   //--- Build Asia session H/L from bars that fall into today's 00:00-07:00 GMT
    void MapAsiaLevels() {
        datetime today = GetGMTDate();

        if(m_asia.valid && m_asia.date == today) return;

        m_asia.high = - 1;
        m_asia.low = - 1;
        m_asia.valid = false;
        m_asia.highSwept = false;
        m_asia.lowSwept = false;
        m_asia.date = today;

        int bars = iBars(m_symbol, m_tf);
        if(bars < 10) return;
        int maxScan = MathMin(bars - 1, 500);
        int counted = 0;

        for(int i = 1; i <= maxScan; i++) {
            datetime barTime = iTime(m_symbol, m_tf, i);
            if(barTime <= 0) continue;

         // Convert bar's server time to GMT
            int gmtH, gmtM;
            ServerTimeToGMTComponents(barTime, gmtH, gmtM);

         // Get the GMT date of this bar
            datetime barGMT = ServerToGMT(barTime);
            MqlDateTime barDt;
            TimeToStruct(barGMT, barDt);
            barDt.hour = 0; barDt.min = 0; barDt.sec = 0;
            datetime barDate = StructToTime(barDt);

         // Only today's Asia bars
            if(barDate != today) {
                if(counted > 0) break; // we've passed today's bars
                continue;
            }

            if(gmtH >= ASIA_H_START && gmtH < ASIA_H_END) {
                double h = iHigh(m_symbol, m_tf, i);
                double l = iLow(m_symbol, m_tf, i);
                if(m_asia.high < 0 || h > m_asia.high) { m_asia.high = h; m_asia.highTime = barTime; }
                    if(m_asia.low < 0 || l < m_asia.low) { m_asia.low = l; m_asia.lowTime = barTime; }
                        counted++;
                    }
                }

                if(counted >= 3 && m_asia.high > 0 && m_asia.low > 0 && m_asia.high > m_asia.low) {
                    m_asia.valid = true;
                    double range = PriceToPips(m_asia.high - m_asia.low);
                    Print(StringFormat("[ % s] Asia mapped: High = % .5f Low = % .5f Range = % .1f pips( % d bars)",
                    m_symbol, m_asia.high, m_asia.low, range, counted));
                } else {
                    Print(StringFormat("[ % s] Asia mapping incomplete: counted = % d high = % .5f low = % .5f",
                    m_symbol, counted, m_asia.high, m_asia.low));
                }
            }

   //--- Check if any of the recent N bars sweeps Asia High or Low
   //--- Sweep = wick pierces beyond level, but candle closes back inside
            bool CheckSweep(ENUM_SIGNAL_DIRECTION &sweepDir) {
                if(!m_asia.valid) return false;

                double sweepMinBuy, sweepMaxBuy, sweepMinSell, sweepMaxSell;
                if(m_isGold) {
                    sweepMinBuy = PipsToPrice(SWEEP_MIN_PIPS_GOLD);
                    sweepMaxBuy = PipsToPrice(SWEEP_MAX_PIPS_GOLD);
                    sweepMinSell = sweepMinBuy;
                    sweepMaxSell = sweepMaxBuy;
                } else if (m_isJPY) {
                    sweepMinBuy = PipsToPrice(SWEEP_MIN_PIPS_JPY);
                    sweepMaxBuy = PipsToPrice(SWEEP_MAX_PIPS_JPY);
                    sweepMinSell = sweepMinBuy;
                    sweepMaxSell = sweepMaxBuy;
                } else {
                    sweepMinBuy = PipsToPrice(SWEEP_MIN_PIPS_FX);
                    sweepMaxBuy = PipsToPrice(SWEEP_MAX_PIPS_FX);
                    sweepMinSell = sweepMinBuy;
                    sweepMaxSell = sweepMaxBuy;
                }

      // Check the last 5 closed bars for sweep
                int barsToCheck = MathMin(5, iBars(m_symbol, m_tf) - 1);

                for(int i = 1; i <= barsToCheck; i++) {
                    double high_i = iHigh(m_symbol, m_tf, i);
                    double low_i = iLow(m_symbol, m_tf, i);
                    double close_i = iClose(m_symbol, m_tf, i);

         // BEARISH: price sweeps ABOVE Asia High, closes back below
                    if(!m_asia.highSwept) {
                        double pierce = high_i - m_asia.high;
                        if(pierce >= sweepMinSell && pierce <= sweepMaxSell) {
                            if(close_i <= m_asia.high) {
                                m_asia.highSwept = true;
                                m_asia.sweepWickTip = high_i;
                                m_asia.sweepTime = iTime(m_symbol, m_tf, i);
                                sweepDir = SIGNAL_SELL;
                                Print(StringFormat("[ % s] SELL SWEEP detected bar[ % d]: Asia High % .5f pierced to % .5f, close % .5f",
                                m_symbol, i, m_asia.high, high_i, close_i));
                                return true;
                            }
                        }
                    }

         // BULLISH: price sweeps BELOW Asia Low, closes back above
                    if(!m_asia.lowSwept) {
                        double pierce = m_asia.low - low_i;
                        if(pierce >= sweepMinBuy && pierce <= sweepMaxBuy) {
                            if(close_i >= m_asia.low) {
                                m_asia.lowSwept = true;
                                m_asia.sweepWickTip = low_i;
                                m_asia.sweepTime = iTime(m_symbol, m_tf, i);
                                sweepDir = SIGNAL_BUY;
                                Print(StringFormat("[ % s] BUY SWEEP detected bar[ % d]: Asia Low % .5f pierced to % .5f, close % .5f",
                                m_symbol, i, m_asia.low, low_i, close_i));
                                return true;
                            }
                        }
                    }
                }
                return false;
            }

   //--- After sweep: look for displacement candle (CHoCH) + FVG/OB
   //--- Scans from most recent bar backward to find displacement after sweep time
            bool DetectCHoCHandFVG(ENUM_SIGNAL_DIRECTION dir, SFVG &fvg) {
                double atr = GetATR(m_tf, 14);
                if(atr <= 0) {
                    Print(StringFormat("[ % s] ATR unavailable", m_symbol));
                    return false;
                }

                double minBody = atr * DISP_ATR_MULT;
                int maxBars = MathMin(iBars(m_symbol, m_tf) - 2, 20);

      // Scan from bar[1] (most recent closed) backward
                for(int i = 1; i < maxBars; i++) {
                    datetime barT = iTime(m_symbol, m_tf, i);
         // Only consider bars after the sweep
                    if(barT <= m_asia.sweepTime) continue;

                    double open_i = iOpen(m_symbol, m_tf, i);
                    double high_i = iHigh(m_symbol, m_tf, i);
                    double low_i = iLow(m_symbol, m_tf, i);
                    double close_i = iClose(m_symbol, m_tf, i);
                    double body = MathAbs(close_i - open_i);

                    if(dir == SIGNAL_BUY) {
            // Need a strong BULLISH displacement candle
                        if(close_i <= open_i) continue;
                        if(body < minBody) continue;

            // FVG check: gap between bar[i+1].high and bar[i-1].low
                        if(i + 1 < maxBars && i - 1 >= 0) {
                            double prevHigh = iHigh(m_symbol, m_tf, i + 1);
                            double nextLow = iLow(m_symbol, m_tf, i - 1);

                            if(prevHigh < nextLow) {
                                fvg.isBullish = true;
                                fvg.lower = prevHigh;
                                fvg.upper = nextLow;
                                fvg.midpoint = (fvg.lower + fvg.upper) / 2.0;
                                fvg.time = barT;
                                fvg.active = true;
                                Print(StringFormat("[ % s] BUY FVG found bar[ % d]: % .5f - % .5f mid = % .5f",
                                m_symbol, i, fvg.lower, fvg.upper, fvg.midpoint));
                                return true;
                            }
                        }

            // No FVG gap, use OB: the last bearish candle before displacement
            // (Order Block = the candle whose orders were absorbed by displacement)
                        for(int j = i + 1; j < i + 5 && j < maxBars; j++) {
                            double ob_open = iOpen(m_symbol, m_tf, j);
                            double ob_close = iClose(m_symbol, m_tf, j);
                            double ob_high = iHigh(m_symbol, m_tf, j);
                            double ob_low = iLow(m_symbol, m_tf, j);
                            if(ob_close < ob_open) { // bearish candle = bullish OB
                                fvg.isBullish = true;
                                fvg.lower = ob_low;
                                fvg.upper = ob_open; // OB body high
                                fvg.midpoint = (ob_low + ob_open) / 2.0;
                                fvg.time = iTime(m_symbol, m_tf, j);
                                fvg.active = true;
                                Print(StringFormat("[ % s] BUY OB found bar[ % d]: % .5f - % .5f mid = % .5f",
                                m_symbol, j, fvg.lower, fvg.upper, fvg.midpoint));
                                return true;
                            }
                        }

            // Fallback: 50% of the displacement candle itself (OTE)
                        fvg.isBullish = true;
                        fvg.lower = low_i;
                        fvg.upper = low_i + (high_i - low_i) * 0.5;
                        fvg.midpoint = low_i + (high_i - low_i) * 0.382;
                        fvg.time = barT;
                        fvg.active = true;
                        Print(StringFormat("[ % s] BUY OTE fallback bar[ % d]: mid = % .5f", m_symbol, i, fvg.midpoint));
                        return true;
                    }

                    if(dir == SIGNAL_SELL) {
            // Need a strong BEARISH displacement candle
                        if(close_i >= open_i) continue;
                        if(body < minBody) continue;

                        if(i + 1 < maxBars && i - 1 >= 0) {
                            double prevLow = iLow(m_symbol, m_tf, i + 1);
                            double nextHigh = iHigh(m_symbol, m_tf, i - 1);

                            if(prevLow > nextHigh) {
                                fvg.isBullish = false;
                                fvg.upper = prevLow;
                                fvg.lower = nextHigh;
                                fvg.midpoint = (fvg.upper + fvg.lower) / 2.0;
                                fvg.time = barT;
                                fvg.active = true;
                                Print(StringFormat("[ % s] SELL FVG found bar[ % d]: % .5f - % .5f mid = % .5f",
                                m_symbol, i, fvg.lower, fvg.upper, fvg.midpoint));
                                return true;
                            }
                        }

            // OB fallback: last bullish candle before bearish displacement
                        for(int j = i + 1; j < i + 5 && j < maxBars; j++) {
                            double ob_open = iOpen(m_symbol, m_tf, j);
                            double ob_close = iClose(m_symbol, m_tf, j);
                            double ob_high = iHigh(m_symbol, m_tf, j);
                            double ob_low = iLow(m_symbol, m_tf, j);
                            if(ob_close > ob_open) { // bullish candle = bearish OB
                                fvg.isBullish = false;
                                fvg.upper = ob_high;
                                fvg.lower = ob_open; // OB body low
                                fvg.midpoint = (ob_high + ob_open) / 2.0;
                                fvg.time = iTime(m_symbol, m_tf, j);
                                fvg.active = true;
                                Print(StringFormat("[ % s] SELL OB found bar[ % d]: % .5f - % .5f mid = % .5f",
                                m_symbol, j, fvg.lower, fvg.upper, fvg.midpoint));
                                return true;
                            }
                        }

                        fvg.isBullish = false;
                        fvg.upper = high_i;
                        fvg.lower = high_i - (high_i - low_i) * 0.5;
                        fvg.midpoint = high_i - (high_i - low_i) * 0.382;
                        fvg.time = barT;
                        fvg.active = true;
                        Print(StringFormat("[ % s] SELL OTE fallback bar[ % d]: mid = % .5f", m_symbol, i, fvg.midpoint));
                        return true;
                    }
                }
                return false;
            }

   //--- Validate spread is acceptable
            bool SpreadOK() {
                double spreadPoints = (double)SymbolInfoInteger(m_symbol, SYMBOL_SPREAD)
                * SymbolInfoDouble(m_symbol, SYMBOL_POINT);
                double spreadPips = PriceToPips(spreadPoints);

                double maxPips;
                if(m_isGold) maxPips = MAX_SPREAD_PIPS_GOLD;
                else if(m_isBTC) maxPips = MAX_SPREAD_PIPS_BTC;
                else maxPips = MAX_SPREAD_PIPS_FX;

                if(spreadPips > maxPips) {
                    Print(StringFormat("[ % s] Spread too wide: % .1f pips(max % .1f)", m_symbol, spreadPips, maxPips));
                    return false;
                }
                return true;
            }

   //--- Find the nearest liquidity target for TP (previous swing H/L, round number, etc.)
            double FindLiquidityTarget(ENUM_SIGNAL_DIRECTION dir, double entry, double minTPDist) {
                int barsToScan = MathMin(100, iBars(m_symbol, m_htf) - 1);

                if(dir == SIGNAL_BUY) {
         // Find the next significant high above entry
                    double bestTarget = entry + minTPDist; // default 1:3
                    for(int i = 1; i < barsToScan; i++) {
                        double h = iHigh(m_symbol, m_htf, i);
                        if(h > entry + minTPDist * 0.8 && h > entry) {
                            double dist = h - entry;
                            if(dist >= minTPDist) {
                                bestTarget = h;
                                break;
                            }
                        }
                    }
                    return bestTarget;
                } else {
                    double bestTarget = entry - minTPDist;
                    for(int i = 1; i < barsToScan; i++) {
                        double l = iLow(m_symbol, m_htf, i);
                        if(l < entry - minTPDist * 0.8 && l < entry) {
                            double dist = entry - l;
                            if(dist >= minTPDist) {
                                bestTarget = l;
                                break;
                            }
                        }
                    }
                    return bestTarget;
                }
            }

   //--- Build the complete setup
            bool BuildSetup(ENUM_SIGNAL_DIRECTION dir, SFVG &fvg, ENUM_SESSION session) {
                int digits = (int)SymbolInfoInteger(m_symbol, SYMBOL_DIGITS);
                double point = SymbolInfoDouble(m_symbol, SYMBOL_POINT);

                double entry = NormalizeDouble(fvg.midpoint, digits);
                double sl;

      // SL: beyond the sweep wick with a small buffer
                double buffer = PipsToPrice(0.5);
                if(m_isGold) buffer = PipsToPrice(1.0);

                if(dir == SIGNAL_BUY) {
                    sl = NormalizeDouble(m_asia.sweepWickTip - buffer, digits);
                    if(entry <= sl) {
                        Print(StringFormat("[ % s] BUY setup rejected: entry % .5f <= SL % .5f", m_symbol, entry, sl));
                        return false;
                    }
                } else {
                    sl = NormalizeDouble(m_asia.sweepWickTip + buffer, digits);
                    if(entry >= sl) {
                        Print(StringFormat("[ % s] SELL setup rejected: entry % .5f >= SL % .5f", m_symbol, entry, sl));
                        return false;
                    }
                }

                double slDist = MathAbs(entry - sl);
                double slPips = PriceToPips(slDist);

      // Validate SL not too wide
                double maxSL;
                if(m_isGold) maxSL = MAX_SL_PIPS_GOLD;
                else if(m_isBTC) maxSL = MAX_SL_PIPS_BTC;
                else if(m_isJPY) maxSL = MAX_SL_PIPS_JPY;
                else maxSL = MAX_SL_PIPS_FOREX;

                if(slPips > maxSL) {
                    Print(StringFormat("[ % s] Setup rejected: SL = % .1f pips > max % .1f", m_symbol, slPips, maxSL));
                    return false;
                }

                if(slPips < 0.3) {
                    Print(StringFormat("[ % s] Setup rejected: SL = % .1f pips too tight", m_symbol, slPips));
                    return false;
                }

      // TP: try to find a liquidity target, minimum 1:3
                double minTPDist = slDist * TARGET_RR;
                double tp;
                double liqTarget = FindLiquidityTarget(dir, entry, minTPDist);

                if(dir == SIGNAL_BUY) {
                    double liqDist = liqTarget - entry;
                    tp = (liqDist >= minTPDist) ? NormalizeDouble(liqTarget, digits)
                    : NormalizeDouble(entry + minTPDist, digits);
                } else {
                    double liqDist = entry - liqTarget;
                    tp = (liqDist >= minTPDist) ? NormalizeDouble(liqTarget, digits)
                    : NormalizeDouble(entry - minTPDist, digits);
                }

                double actualRR = MathAbs(tp - entry) / slDist;

                m_setup.direction = dir;
                m_setup.entryPrice = entry;
                m_setup.stopLoss = sl;
                m_setup.takeProfit = tp;
                m_setup.riskReward = actualRR;
                m_setup.slPips = slPips;
                m_setup.fvg = fvg;
                m_setup.fvgFound = true;
                m_setup.chochDone = true;
                m_setup.session = session;
                m_setup.setupTime = TimeCurrent();
                m_setup.phase = PHASE_CONFIRMED;
                m_setup.reason = StringFormat(" % s sweep + CHoCH + % s SL = % .1fpips RR = 1: % .1f",
                (session == SESSION_LONDON_KILL ? "London" : "NY"),
                (fvg.active ? "FVG" : "OB"),
                slPips, actualRR);

                Print(StringFormat("[ % s] === SETUP CONFIRMED ===", m_symbol));
                Print(StringFormat("[ % s] Dir = % s Entry = % .5f SL = % .5f TP = % .5f SL = % .1fpips RR = 1: % .1f",
                m_symbol, (dir == SIGNAL_BUY ? "BUY" : "SELL"),
                entry, sl, tp, slPips, actualRR));
                return true;
            }

            public:
            CSilverBullet(string symbol, ENUM_TIMEFRAMES tf, ENUM_TIMEFRAMES htf) {
                m_symbol = symbol;
                m_tf = tf;
                m_htf = htf;
                m_biasTF = PERIOD_H1;

                m_isGold = (StringFind(symbol, "XAU") >= 0 || StringFind(symbol, "GOLD") >= 0);
                m_isJPY = (StringFind(symbol, "JPY") >= 0);
                m_isBTC = (StringFind(symbol, "BTC") >= 0);

      // pip size: JPY = 0.01, Gold = 0.1 (or 0.01 for some brokers), others = 0.0001
                if(m_isGold) m_pipSize = 0.10;
                else if(m_isJPY) m_pipSize = 0.01;
                else if(m_isBTC) m_pipSize = 1.0;
                else m_pipSize = 0.0001;

                m_gmtOffsetSec = DetectGMTOffset();

                ZeroMemory(m_asia);
                ZeroMemory(m_setup);
                m_setup.phase = PHASE_IDLE;

                Print(StringFormat("[ % s] Engine init: pipSize = % .5f gmtOffset = % + dh gold = % s jpy = % s",
                symbol, m_pipSize, m_gmtOffsetSec / 3600, m_isGold?"Y":"N", m_isJPY?"Y":"N"));
            }

   //--- Main update, called on every new M5 bar. Returns true if setup ready.
            bool Update() {
                ENUM_SESSION session = GetCurrentSession();

      //--- During Asia: map levels
                if(session == SESSION_ASIA) {
                    MapAsiaLevels();
                    if(m_setup.phase == PHASE_IDLE)
                    m_setup.phase = PHASE_WATCHING;
                    return false;
                }

      //--- Outside killzones: idle but don't block future sessions
                if(session != SESSION_LONDON_KILL && session != SESSION_NY_KILL) {
                    return false;
                }

      //--- Already in trade or have confirmed setup waiting
                if(m_setup.phase == PHASE_CONFIRMED || m_setup.phase == PHASE_IN_TRADE)
                return false;

      //--- Need Asia levels
                if(!m_asia.valid) {
                    MapAsiaLevels();
                    if(!m_asia.valid) return false;
                }

      //--- Spread check
                if(!SpreadOK()) return false;

      //--- H1 bias filter (optional but improves accuracy)
                ENUM_HTF_BIAS bias = GetH1Bias();

      //--- Phase: watching / idle -> look for sweep
                if(m_setup.phase == PHASE_WATCHING || m_setup.phase == PHASE_IDLE ||
                m_setup.phase == PHASE_DONE) {
                    ENUM_SIGNAL_DIRECTION sweepDir = SIGNAL_NONE;
                    if(CheckSweep(sweepDir)) {
            // Bias confluence check: prefer trades aligned with H1
                        if(bias != BIAS_NONE) {
                            if(sweepDir == SIGNAL_BUY && bias == BIAS_BEARISH) {
                                Print(StringFormat("[ % s] BUY sweep found but H1 bias is BEARISH - proceeding with caution", m_symbol));
                            }
                            if(sweepDir == SIGNAL_SELL && bias == BIAS_BULLISH) {
                                Print(StringFormat("[ % s] SELL sweep found but H1 bias is BULLISH - proceeding with caution", m_symbol));
                            }
                        }
                        m_setup.direction = sweepDir;
                        m_setup.phase = PHASE_SWEPT;
            // Don't return false here -- immediately try to find CHoCH+FVG
            // because the displacement might already be on the chart
                    }
                }

      //--- Phase: swept -> look for CHoCH + FVG/OB
                if(m_setup.phase == PHASE_SWEPT) {
                    SFVG fvg;
                    ZeroMemory(fvg);
                    if(DetectCHoCHandFVG(m_setup.direction, fvg)) {
                        if(BuildSetup(m_setup.direction, fvg, session)) {
                            return true;
                        }
                    }

         // Timeout: if no CHoCH found in N bars, reset and keep watching
                    int barsSinceSweep = 0;
                    if(m_asia.sweepTime > 0) {
                        barsSinceSweep = (int)((TimeCurrent() - m_asia.sweepTime) / PeriodSeconds(m_tf));
                    }
                    if(barsSinceSweep > MAX_BARS_AFTER_SWEEP) {
                        Print(StringFormat("[ % s] CHoCH timeout after % d bars, resetting", m_symbol, barsSinceSweep));
                        m_setup.phase = PHASE_WATCHING;
            // Allow the same level to be swept again
                        if(m_setup.direction == SIGNAL_BUY) m_asia.lowSwept = false;
                        if(m_setup.direction == SIGNAL_SELL) m_asia.highSwept = false;
                    }
                }

                return false;
            }

   //--- Getters
            SSetup GetSetup() { return m_setup; }
                SAsiaLevels GetAsiaLevels() { return m_asia; }
                    bool HasSetup() { return(m_setup.phase == PHASE_CONFIRMED); }
                        bool IsInKillzone() {
                            ENUM_SESSION s = GetCurrentSession();
                            return(s == SESSION_LONDON_KILL || s == SESSION_NY_KILL);
                        }
                        ENUM_SESSION GetSession() { return GetCurrentSession(); }
                            string GetSessionName() {
                                switch(GetCurrentSession()) {
                                    case SESSION_LONDON_KILL: return "London Killzone";
                                    case SESSION_NY_KILL: return "NY Killzone";
                                    case SESSION_ASIA: return "Asia(Mapping)";
                                    default: return "Off - Session";
                                }
                            }

                            void OnTradePlaced() {
                                m_setup.phase = PHASE_IN_TRADE;
                            }

                            void OnTradeClose() {
                                m_setup.phase = PHASE_WATCHING;
                            }

                            void ResetSession() {
                                m_setup.phase = PHASE_WATCHING;
                                m_asia.highSwept = false;
                                m_asia.lowSwept = false;
                                Print(StringFormat("[ % s] Session reset, ready for new setups", m_symbol));
                            }

                            void ResetDay() {
                                ZeroMemory(m_asia);
                                ZeroMemory(m_setup);
                                m_setup.phase = PHASE_IDLE;
                                m_gmtOffsetSec = DetectGMTOffset(); // re - detect in case of DST change
                                Print(StringFormat("[ % s] New day reset", m_symbol));
                            }

                            bool IsFVGStillValid() {
                                if(m_setup.phase != PHASE_CONFIRMED) return false;
                                double bid = SymbolInfoDouble(m_symbol, SYMBOL_BID);
                                if(m_setup.direction == SIGNAL_BUY)
                                return(bid > m_setup.stopLoss);
                                else
                                return(bid < m_setup.stopLoss);
                            }

                            double GetCurrentATR() { return GetATR(m_tf, 14); }
                            };

#endif
