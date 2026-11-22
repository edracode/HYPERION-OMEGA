#ifndef VELOX_LONDON_MQH
#define VELOX_LONDON_MQH

long LastSundayAt0100UTC(const int year, const int month)
{
   MqlDateTime date = {};
   date.year = year;
   date.mon = month;
   date.day = 31;
   date.hour = 1;
   const datetime through = StructToTime(date);
   TimeToStruct(through, date);
   return (long)through - date.day_of_week * 86400;
}

long LondonOffset(const long seconds)
{
   MqlDateTime date;
   TimeToStruct((datetime)seconds, date);
   if(seconds >= LastSundayAt0100UTC(date.year, 3) && seconds < LastSundayAt0100UTC(date.year, 10))
      return 3600;
   return 0;
}

void ProcessLondon(const long utc_now, const int server_offset, const datetime holdout,
                   const double extra_cost, const int output, long &last_day, int &sessions,
                   int &passing, int &holdout_passing, double &totals[])
{
   const long local_now = utc_now + LondonOffset(utc_now);
   const long day = local_now / 86400;
   const long london_midnight = day * 86400;
   if(day <= last_day || local_now - london_midnight < 16 * 3600 + 31 * 60) return;
   last_day = day;
   const int weekday = (int)((day + 3) % 7);
   if(weekday > 4) return;

   const long session_midnight = london_midnight - LondonOffset(london_midnight + 12 * 3600);
   const long start = (session_midnight + 11 * 3600 + 30 * 60) * 1000;
   const long placement = (session_midnight + 13 * 3600) * 1000;
   const long cutoff = (session_midnight + 15 * 3600 + 30 * 60) * 1000;
   const long close = (session_midnight + 16 * 3600 + 30 * 60) * 1000;
   const long server_shift = server_offset * 60000;
   const string date = TimeToString((datetime)london_midnight, TIME_DATE);
   const string partition = london_midnight < (long)holdout ? "TRAIN" : "HOLDOUT";
   const double pip = StringFind(_Symbol, "USDJPY") >= 0 ||
                      SymbolInfoString(_Symbol, SYMBOL_CURRENCY_PROFIT) == "JPY" ? 0.01 : 0.0001;

   MqlTick ticks[];
   const int size = CopyTicksRange(_Symbol, ticks, COPY_TICKS_INFO,
                                  (ulong)(start + server_shift), (ulong)(close + 59999 + server_shift));
   sessions++;
   string coverage = "PASS", regime = "";
   int used = 0, pre = 0;
   long first_at = 0, last_at = 0;
   bool gap = false;
   double low = 0, high = 0, first_bid = 0, last_bid = 0;
   for(int i = 0; i < size; i++)
   {
      const long stamp = ticks[i].time_msc - server_shift;
      if(ticks[i].bid <= 0 || ticks[i].ask < ticks[i].bid || stamp < start || stamp > close + 59999) continue;
      if(used == 0) first_at = stamp;
      else if(stamp - last_at > 60000) gap = true;
      last_at = stamp;
      ticks[used] = ticks[i];
      ticks[used].time_msc = stamp;
      used++;
      if(stamp >= placement) continue;
      const double bid = ticks[i].bid;
      if(pre == 0)
      {
         first_bid = low = high = bid;
      }
      else
      {
         low = MathMin(low, bid);
         high = MathMax(high, bid);
      }
      pre++;
      last_bid = bid;
   }
   if(size < 0) coverage = "TICKS_UNAVAILABLE";
   else if(used == 0) coverage = "NO_SESSION_QUOTES";
   else if(first_at - start > 60000) coverage = "LATE_FIRST_QUOTE";
   else if(last_at < close) coverage = "NO_CLOSE_QUOTE";
   else if(gap) coverage = "INTERNAL_GAP";
   if(coverage == "PASS")
   {
      passing++;
      if(pre >= 2 && high > low)
      {
         regime = MathAbs(last_bid - first_bid) / (high - low) >= 0.5 ? "DIRECTIONAL" : "SIDEWAYS_PROXY";
         if(partition == "HOLDOUT") holdout_passing++;
      }
   }

   string modes[3] = {"BUY", "SELL", "BOTH"};
   for(int mode = 0; mode < 3; mode++)
   {
      string disposition = "EXCLUDED", side = "", entered = "", exited = "";
      double pips = 0, mid_pips = 0, after_cost = 0;
      if(coverage == "PASS" && regime == "") disposition = "EXCLUDED_FLAT_OR_EMPTY_RANGE";
      if(coverage == "PASS" && regime != "")
      {
         disposition = "NO_TRIGGER";
         for(int i = 0; i < used; i++)
         {
            const long stamp = ticks[i].time_msc;
            if(stamp < placement) continue;
            if(stamp >= cutoff) break;
            const bool buy = mode != 1 && ticks[i].ask >= high;
            const bool sell = mode != 0 && ticks[i].bid <= low;
            if(!buy && !sell) continue;
            if(buy && sell)
            {
               disposition = "AMBIGUOUS_BOTH_TRIGGERED";
               break;
            }
            const double entry_price = buy ? ticks[i].ask : ticks[i].bid;
            const double entry_mid = (ticks[i].ask + ticks[i].bid) / 2;
            const int sign = buy ? 1 : -1;
            for(int j = i; j < used; j++)
            {
               const double exit_price = buy ? ticks[j].bid : ticks[j].ask;
               const bool stop = buy ? exit_price <= low : exit_price >= high;
               if(!stop && ticks[j].time_msc < close) continue;
               disposition = stop ? "STOP" : "TIME_EXIT";
               side = buy ? "BUY" : "SELL";
               entered = IntegerToString(stamp);
               exited = IntegerToString(ticks[j].time_msc);
               pips = NormalizeDouble(sign * (exit_price - entry_price) / pip, 6);
               mid_pips = NormalizeDouble(sign * ((ticks[j].ask + ticks[j].bid) / 2 - entry_mid) / pip, 6);
               after_cost = pips - extra_cost;
               if(partition == "HOLDOUT") totals[mode] += after_cost;
               break;
            }
            break;
         }
      }
      FileWrite(output, date, partition, modes[mode], coverage, regime, disposition, side,
                entered, exited, DoubleToString(pips, 6), DoubleToString(mid_pips, 6),
                DoubleToString(after_cost, 6));
   }
}
#endif
