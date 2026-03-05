//+------------------------------------------------------------------+
//|                                                      Logger.mqh |
//|           On-Chart Dashboard for SMC Scalper EA v4.0            |
//+------------------------------------------------------------------+
#ifndef LOGGER_MQH
#define LOGGER_MQH

#include "Defines.mqh"

class CLogger {
    private:
    string m_prefix;
    color m_colorBull;
    color m_colorBear;
    color m_colorInfo;
    color m_colorWarn;
    color m_colorBG;

    void CreateLabel(string name, string text, int x, int y, color clr, int fontSize = 9) {
        string fullName = m_prefix + name;
        if(ObjectFind(0, fullName) < 0) {
            ObjectCreate(0, fullName, OBJ_LABEL, 0, 0, 0);
            ObjectSetInteger(0, fullName, OBJPROP_CORNER, CORNER_LEFT_UPPER);
            ObjectSetInteger(0, fullName, OBJPROP_XDISTANCE, x);
            ObjectSetInteger(0, fullName, OBJPROP_YDISTANCE, y);
            ObjectSetInteger(0, fullName, OBJPROP_BACK, false);
            ObjectSetInteger(0, fullName, OBJPROP_SELECTABLE, false);
        }
        ObjectSetString(0, fullName, OBJPROP_TEXT, text);
        ObjectSetInteger(0, fullName, OBJPROP_COLOR, clr);
        ObjectSetInteger(0, fullName, OBJPROP_FONTSIZE, fontSize);
        ObjectSetString(0, fullName, OBJPROP_FONT, "Consolas");
    }

    void CreateRect(string name, int x, int y, int w, int h, color clr) {
        string fullName = m_prefix + name;
        if(ObjectFind(0, fullName) < 0) {
            ObjectCreate(0, fullName, OBJ_RECTANGLE_LABEL, 0, 0, 0);
            ObjectSetInteger(0, fullName, OBJPROP_CORNER, CORNER_LEFT_UPPER);
            ObjectSetInteger(0, fullName, OBJPROP_XDISTANCE, x);
            ObjectSetInteger(0, fullName, OBJPROP_YDISTANCE, y);
            ObjectSetInteger(0, fullName, OBJPROP_XSIZE, w);
            ObjectSetInteger(0, fullName, OBJPROP_YSIZE, h);
            ObjectSetInteger(0, fullName, OBJPROP_BGCOLOR, clr);
            ObjectSetInteger(0, fullName, OBJPROP_BORDER_TYPE, BORDER_FLAT);
            ObjectSetInteger(0, fullName, OBJPROP_BACK, true);
            ObjectSetInteger(0, fullName, OBJPROP_SELECTABLE, false);
        }
    }

    public:
    CLogger() {
        m_prefix = "SMC_";
        m_colorBull = clrLimeGreen;
        m_colorBear = clrTomato;
        m_colorInfo = clrSilver;
        m_colorWarn = clrGold;
        m_colorBG = C'20, 20, 30';
    }

    void Init() {
        CreateRect("BG", 5, 20, 290, 320, m_colorBG);
    }

    void UpdateDashboard(
    string symbol,
    string sessionName,
    string phase,
    double asiaHigh,
    double asiaLow,
    double balance,
    double dayPnL,
    double dayPnLPct,
    int tradesToday,
    int consecLosses,
    int consecWins,
    double sizeMult,
    bool isTargetHit,
    bool isLossHit,
    string lastSetupReason,
    ENUM_SIGNAL_DIRECTION lastDir
    ) {
        int x = 10, y = 25, dy = 18;
        int row = 0;

        CreateLabel("title", "=== SMC SCALPER EA ===", x, y + row * dy, clrGold, 10);
        row++;
        CreateLabel("ver", EA_NAME + " v" + EA_VERSION, x, y + row * dy, clrDimGray, 8);
        row++;

      // GMT time
        MqlDateTime dt;
        TimeToStruct(TimeGMT(), dt);
        CreateLabel("time", StringFormat("GMT: % 02d: % 02d", dt.hour, dt.min), x + 160, y + (row - 1) * dy, clrDimGray, 8);

        color sesClr = (StringFind(sessionName, "Killzone") >= 0) ? clrLimeGreen : clrDimGray;
        CreateLabel("session", "Session : " + sessionName, x, y + row * dy, sesClr);
        row++;
        CreateLabel("phase", "Phase : " + phase, x, y + row * dy, clrSilver);
        row++;

        CreateLabel("sep1", "----------------------------", x, y + row * dy, clrDimGray, 8);
        row++;

        int asiaDigits = (StringFind(symbol, "JPY") >= 0) ? 3 : 5;
        string hiStr = (asiaHigh > 0) ? DoubleToString(asiaHigh, asiaDigits) : "---";
        string loStr = (asiaLow > 0 && asiaLow < 9999) ? DoubleToString(asiaLow, asiaDigits) : "---";
        CreateLabel("ashi", "Asia High: " + hiStr, x, y + row * dy,
        asiaHigh > 0 ? clrLightYellow : clrDimGray);
        row++;
        CreateLabel("aslo", "Asia Low : " + loStr, x, y + row * dy,
        (asiaLow > 0 && asiaLow < 9999) ? clrLightYellow : clrDimGray);
        row++;

        CreateLabel("sep2", "----------------------------", x, y + row * dy, clrDimGray, 8);
        row++;
        CreateLabel("bal", StringFormat("Balance : $ % .2f", balance), x, y + row * dy, clrSilver);
        row++;

        color pnlClr = (dayPnL >= 0) ? m_colorBull : m_colorBear;
        CreateLabel("pnl", StringFormat("Day P&L : % + .2f % % ($ % + .2f)", dayPnLPct, dayPnL),
        x, y + row * dy, pnlClr);
        row++;
        CreateLabel("trades", StringFormat("Trades : % d today", tradesToday), x, y + row * dy, clrSilver);
        row++;

        CreateLabel("sep3", "----------------------------", x, y + row * dy, clrDimGray, 8);
        row++;

        string statusStr;
        color statusClr;
        if(isTargetHit) { statusStr = "STATUS: TARGET HIT"; statusClr = clrLimeGreen; }
            else if(isLossHit) { statusStr = "STATUS: LOSS LIMIT"; statusClr = clrTomato; }
                else if(sizeMult < 1.0) { statusStr = "STATUS: REDUCED SIZE"; statusClr = clrGold; }
                    else { statusStr = "STATUS: ACTIVE"; statusClr = clrLimeGreen; }
                        CreateLabel("status", statusStr, x, y + row * dy, statusClr);
                        row++;

                        CreateLabel("streak",
                        StringFormat("Streak : % dW / % dL x % .1f", consecWins, consecLosses, sizeMult),
                        x, y + row * dy, clrSilver);
                        row++;

                        CreateLabel("sep4", "----------------------------", x, y + row * dy, clrDimGray, 8);
                        row++;

                        color dirClr = (lastDir == SIGNAL_BUY) ? m_colorBull
                        : (lastDir == SIGNAL_SELL) ? m_colorBear : clrDimGray;
                        string dirStr = (lastDir == SIGNAL_BUY) ? "BUY"
                        : (lastDir == SIGNAL_SELL) ? "SELL" : "none";
                        CreateLabel("lastdir", "Last : " + dirStr, x, y + row * dy, dirClr);
                        row++;
                        CreateLabel("lastreason", lastSetupReason, x, y + row * dy, clrDimGray, 8);

                        ChartRedraw(0);
                    }

                    void DrawAsiaLevels(string symbol, double asiaHigh, double asiaLow) {
                        if(asiaHigh <= 0 || asiaLow <= 0) return;

                        string nameH = m_prefix + symbol + "_AsiaHigh";
                        string nameL = m_prefix + symbol + "_AsiaLow";

                        datetime t1 = iTime(symbol, PERIOD_M5, 100);
                        datetime t2 = TimeCurrent() + 3600 * 4;

                        if(ObjectFind(0, nameH) < 0)
                        ObjectCreate(0, nameH, OBJ_TREND, 0, t1, asiaHigh, t2, asiaHigh);
                        ObjectSetDouble(0, nameH, OBJPROP_PRICE, 0, asiaHigh);
                        ObjectSetDouble(0, nameH, OBJPROP_PRICE, 1, asiaHigh);
                        ObjectSetInteger(0, nameH, OBJPROP_COLOR, clrGold);
                        ObjectSetInteger(0, nameH, OBJPROP_STYLE, STYLE_DASH);
                        ObjectSetInteger(0, nameH, OBJPROP_WIDTH, 1);
                        ObjectSetString(0, nameH, OBJPROP_TEXT, "Asia High");
                        ObjectSetInteger(0, nameH, OBJPROP_RAY_RIGHT, true);

                        if(ObjectFind(0, nameL) < 0)
                        ObjectCreate(0, nameL, OBJ_TREND, 0, t1, asiaLow, t2, asiaLow);
                        ObjectSetDouble(0, nameL, OBJPROP_PRICE, 0, asiaLow);
                        ObjectSetDouble(0, nameL, OBJPROP_PRICE, 1, asiaLow);
                        ObjectSetInteger(0, nameL, OBJPROP_COLOR, clrOrangeRed);
                        ObjectSetInteger(0, nameL, OBJPROP_STYLE, STYLE_DASH);
                        ObjectSetInteger(0, nameL, OBJPROP_WIDTH, 1);
                        ObjectSetString(0, nameL, OBJPROP_TEXT, "Asia Low");
                        ObjectSetInteger(0, nameL, OBJPROP_RAY_RIGHT, true);

                        ChartRedraw(0);
                    }

                    void DrawFVG(string symbol, double upper, double lower, bool isBullish, datetime t) {
                        string name = m_prefix + symbol + "_FVG_" + IntegerToString((int)t);
                        if(ObjectFind(0, name) >= 0) return;

                        datetime t2 = t + PeriodSeconds(PERIOD_M5) * 10;
                        ObjectCreate(0, name, OBJ_RECTANGLE, 0, t, upper, t2, lower);
                        ObjectSetInteger(0, name, OBJPROP_COLOR, isBullish ? C'0, 100, 0' : C'100, 0, 0');
                        ObjectSetInteger(0, name, OBJPROP_FILL, true);
                        ObjectSetInteger(0, name, OBJPROP_BACK, true);
                        ObjectSetInteger(0, name, OBJPROP_STYLE, STYLE_SOLID);
                        ObjectSetInteger(0, name, OBJPROP_SELECTABLE, false);
                        ChartRedraw(0);
                    }

                    void DrawSweepArrow(string symbol, bool isBullish, double price, datetime t) {
                        string name = m_prefix + symbol + "_Sweep_" + IntegerToString((int)t);
                        if(ObjectFind(0, name) >= 0) return;

                        ObjectCreate(0, name, OBJ_ARROW, 0, t, price);
                        ObjectSetInteger(0, name, OBJPROP_ARROWCODE, isBullish ? 233 : 234);
                        ObjectSetInteger(0, name, OBJPROP_COLOR, isBullish ? clrLimeGreen : clrTomato);
                        ObjectSetInteger(0, name, OBJPROP_WIDTH, 3);
                        ObjectSetInteger(0, name, OBJPROP_SELECTABLE, false);
                        ChartRedraw(0);
                    }

                    void Cleanup() {
                        ObjectsDeleteAll(0, m_prefix);
                        ChartRedraw(0);
                    }
                };
#endif
