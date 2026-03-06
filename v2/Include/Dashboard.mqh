//+------------------------------------------------------------------+
//|                                                  Dashboard.mqh  |
//|       Institutional EA v2 — On-Chart Display & Logging          |
//+------------------------------------------------------------------+
#ifndef DASHBOARD_V2_MQH
#define DASHBOARD_V2_MQH

#include "Defines.mqh"

class CDashboard {
private:
   string m_prefix;
   int    m_fontSize;
   color  m_colHead;
   color  m_colOK;
   color  m_colWarn;
   color  m_colBad;
   color  m_colFVG_Bull;
   color  m_colFVG_Bear;

   //-----------------------------------------------------------
   void Label(string name, string text, int x, int y, color clr,
              int fontSize = 0, string anchor = "") {
      string objName = m_prefix + name;
      if(ObjectFind(0, objName) < 0)
         ObjectCreate(0, objName, OBJ_LABEL, 0, 0, 0);
      ObjectSetInteger(0, objName, OBJPROP_CORNER, CORNER_LEFT_UPPER);
      ObjectSetInteger(0, objName, OBJPROP_XDISTANCE, x);
      ObjectSetInteger(0, objName, OBJPROP_YDISTANCE, y);
      ObjectSetInteger(0, objName, OBJPROP_COLOR, clr);
      ObjectSetInteger(0, objName, OBJPROP_FONTSIZE, fontSize > 0 ? fontSize : m_fontSize);
      ObjectSetInteger(0, objName, OBJPROP_BACK, false);
      ObjectSetString(0, objName, OBJPROP_TEXT, text);
      ObjectSetString(0, objName, OBJPROP_FONT, "Consolas");
   }

   void DrawHLine(string name, double price, color clr, ENUM_LINE_STYLE style = STYLE_DASH) {
      string objName = m_prefix + name;
      if(ObjectFind(0, objName) < 0)
         ObjectCreate(0, objName, OBJ_HLINE, 0, 0, price);
      ObjectSetDouble(0, objName, OBJPROP_PRICE, price);
      ObjectSetInteger(0, objName, OBJPROP_COLOR, clr);
      ObjectSetInteger(0, objName, OBJPROP_STYLE, style);
      ObjectSetInteger(0, objName, OBJPROP_WIDTH, 1);
      ObjectSetInteger(0, objName, OBJPROP_BACK, true);
   }

   void DrawBox(string name, datetime t1, double p1,
                datetime t2, double p2, color clr) {
      string objName = m_prefix + name;
      if(ObjectFind(0, objName) < 0)
         ObjectCreate(0, objName, OBJ_RECTANGLE, 0, t1, p1, t2, p2);
      ObjectSetInteger(0, objName, OBJPROP_TIME,  0, t1);
      ObjectSetDouble(0, objName,  OBJPROP_PRICE, 0, p1);
      ObjectSetInteger(0, objName, OBJPROP_TIME,  1, t2);
      ObjectSetDouble(0, objName,  OBJPROP_PRICE, 1, p2);
      ObjectSetInteger(0, objName, OBJPROP_COLOR, clr);
      ObjectSetInteger(0, objName, OBJPROP_FILL,  true);
      ObjectSetInteger(0, objName, OBJPROP_BACK,  true);
      ObjectSetInteger(0, objName, OBJPROP_WIDTH, 1);
   }

public:
   CDashboard() {
      m_prefix    = "INST_V2_";
      m_fontSize  = 9;
      m_colHead   = clrSilver;
      m_colOK     = clrLimeGreen;
      m_colWarn   = clrOrange;
      m_colBad    = clrRed;
      m_colFVG_Bull = (color)0x1A3300; // dark green tint
      m_colFVG_Bear = (color)0x1A0000; // dark red tint
   }

   void Init() {
      // Panel background rectangle
      string bg = m_prefix + "BG";
      if(ObjectFind(0, bg) < 0) ObjectCreate(0, bg, OBJ_RECTANGLE_LABEL, 0, 0, 0);
      ObjectSetInteger(0, bg, OBJPROP_CORNER,    CORNER_LEFT_UPPER);
      ObjectSetInteger(0, bg, OBJPROP_XDISTANCE, 5);
      ObjectSetInteger(0, bg, OBJPROP_YDISTANCE, 5);
      ObjectSetInteger(0, bg, OBJPROP_XSIZE,     280);
      ObjectSetInteger(0, bg, OBJPROP_YSIZE,     245);
      ObjectSetInteger(0, bg, OBJPROP_BGCOLOR,   (color)0x0D0D0D);
      ObjectSetInteger(0, bg, OBJPROP_BORDER_COLOR, clrDimGray);
      ObjectSetInteger(0, bg, OBJPROP_BORDER_TYPE, BORDER_FLAT);
      ObjectSetInteger(0, bg, OBJPROP_BACK, false);
   }

   //-----------------------------------------------------------
   // MAIN DASHBOARD UPDATE
   //-----------------------------------------------------------
   void Update(
      string symbol,
      string session,
      ENUM_HTF_BIAS bias,
      ENUM_REGIME regime,
      double balance,
      double dayPnL,
      double dayPnLPct,
      int tradesOpened,
      int losses,
      int wins,
      double sizeMult,
      bool lossHit,
      string lastReason,
      ENUM_SIGNAL_DIR lastDir,
      int confluenceScore
   ) {
      int x = 12, y = 12;
      int lh = 14; // line height

      // Title
      Label("T0", StringFormat("═ INST EA v2 ═  %s", symbol), x, y, m_colHead, 10);
      y += lh + 4;

      // Session & Bias
      color bc = (bias == BIAS_BULLISH) ? m_colOK : (bias == BIAS_BEARISH ? m_colBad : m_colWarn);
      string biasStr = (bias == BIAS_BULLISH) ? "▲ BULL" : (bias == BIAS_BEARISH ? "▼ BEAR" : "─ NEUT");
      string regStr  = EnumToString(regime);
      StringReplace(regStr, "REGIME_", "");
      Label("T1", StringFormat("Session: %-12s", session), x, y, m_colHead); y += lh;
      Label("T2", StringFormat("Bias:    %-12s", biasStr),  x, y, bc);       y += lh;
      Label("T3", StringFormat("Regime:  %-12s", regStr),   x, y, m_colHead);y += lh;
      Label("T4", StringFormat("Score:   %d/100",confluenceScore), x, y,
            (confluenceScore >= MIN_CONFLUENCE_SCORE ? m_colOK : m_colWarn));  y += lh + 3;

      // ─── separator ───
      Label("SEP1", "────────────────────────────", x, y, clrDimGray); y += lh;

      // P&L
      color pnlColor = (dayPnLPct >= 0) ? m_colOK : (lossHit ? m_colBad : m_colWarn);
      Label("P1", StringFormat("Balance:  $%.2f", balance),          x, y, m_colHead); y += lh;
      Label("P2", StringFormat("Day P&L:  %+.2f  (%+.1f%%)", dayPnL, dayPnLPct), x, y, pnlColor); y += lh;
      if(lossHit)
         Label("P3", "  *** DAILY LOSS CAP HIT ***", x, y, m_colBad);
      else
         Label("P3", StringFormat("Trades:  %d  W:%d L:%d  x%.1f", tradesOpened, wins, losses, sizeMult),
               x, y, m_colHead);
      y += lh + 3;

      // ─── separator ───
      Label("SEP2", "────────────────────────────", x, y, clrDimGray); y += lh;

      // Last signal
      string dirStr = (lastDir == DIR_BUY) ? "▲ BUY" : (lastDir == DIR_SELL ? "▼ SELL" : "─");
      Label("S1", StringFormat("Signal: %s", dirStr), x, y,
            (lastDir == DIR_BUY ? m_colOK : (lastDir == DIR_SELL ? m_colBad : m_colHead))); y += lh;

      // Truncate reason if long
      string shortReason = lastReason;
      if(StringLen(shortReason) > 34) shortReason = StringSubstr(shortReason, 0, 34) + "…";
      Label("S2", shortReason, x, y, clrDimGray, 8);

      ChartRedraw(0);
   }

   //-----------------------------------------------------------
   // DRAW ASIA LEVELS
   //-----------------------------------------------------------
   void DrawAsiaLevels(string symbol, double hi, double lo) {
      if(symbol != _Symbol) return;
      if(hi > 0) DrawHLine("asiaH", hi, clrSlateBlue, STYLE_DASH);
      if(lo > 0) DrawHLine("asiaL", lo, clrSlateBlue, STYLE_DASH);
   }

   //-----------------------------------------------------------
   // DRAW FVG BOX
   //-----------------------------------------------------------
   void DrawFVG(string symbol, double upper, double lower,
                bool isBullish, datetime t) {
      if(symbol != _Symbol) return;
      datetime t2 = TimeCurrent() + PeriodSeconds(PERIOD_H1) * 12;
      color clr = isBullish ? m_colFVG_Bull : m_colFVG_Bear;
      DrawBox("fvg", t, lower, t2, upper, clr);
   }

   //-----------------------------------------------------------
   // CLEANUP
   //-----------------------------------------------------------
   void Cleanup() {
      ObjectsDeleteAll(0, m_prefix);
   }
};

#endif // DASHBOARD_V2_MQH
