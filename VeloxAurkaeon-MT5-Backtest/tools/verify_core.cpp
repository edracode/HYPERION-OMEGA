#include <algorithm>
#include <cmath>
#include <iomanip>
#include <iostream>
#include <string>

using std::string;
template<typename A, typename B> double MathMin(A a, B b) { return std::min(double(a), double(b)); }
template<typename A, typename B> double MathMax(A a, B b) { return std::max(double(a), double(b)); }
double MathAbs(double x) { return std::abs(x); }
double MathCeil(double x) { return std::ceil(x); }
double MathFloor(double x) { return std::floor(x); }
double MathSqrt(double x) { return std::sqrt(x); }
double MathRound(double x) { return std::round(x); }
bool MathIsValidNumber(double x) { return std::isfinite(x); }

#include "../MQL5/Experts/VeloxAurkaeon/VeloxCore.mqh"

void WriteFill(const Fill &f)
{
    if (f.side)
        std::cout << "F " << f.entered << ' ' << f.exited << ' ' << f.side << ' ' << f.lots << ' '
                  << f.entry << ' ' << f.exit_price << ' ' << f.gross << ' ' << f.commission << ' '
                  << f.swap_cost << ' ' << f.net << ' ' << f.signal_known_at << ' ' << f.reason << '\n';
}

int main()
{
    int policy, window, interval, mode;
    RiskLimits limits{};
    limits.starting_equity = 10000;
    limits.risk_per_trade = 0.0025;
    limits.max_daily = 0.01;
    limits.max_weekly = 0.025;
    limits.max_drawdown = 0.05;
    limits.max_open_risk = 0.01;
    limits.margin_reserve = 0.5;
    limits.slippage_ticks = 2;
    if (!(std::cin >> mode >> policy >> window >> interval >> limits.first_trade_bar >>
          limits.delay_bars >> limits.max_signal_age >> limits.entry_lot_cap))
        return 2;
    const Contract spec{0.01, 1, 0.1, 0.01, 1, 0.01, 5000, 7, 0.5, 5};
    VeloxReplay replay;
    VeloxSignals signals;
    replay.Configure(static_cast<VeloxPolicy>(policy), spec, limits, window, 2000, interval);
    signals.Configure(static_cast<VeloxPolicy>(policy), window, 2000, interval);
    std::cout << std::setprecision(17);
    ReplayBar bar;
    while (std::cin >> bar.opened >> bar.closed >> bar.bid_open >> bar.bid_high >> bar.bid_low >>
           bar.bid_close >> bar.ask_open >> bar.ask_high >> bar.ask_low >> bar.ask_close >>
           bar.buy_swap >> bar.sell_swap) {
        if (mode == 0) {
            Intent signal;
            signals.Push(bar, signal);
            if (signal.side)
                std::cout << "S " << bar.closed << ' ' << signal.side << ' ' << signal.stop << ' '
                          << signal.target << ' ' << signal.hold_bars << '\n';
        } else {
            Fill first, second;
            string rejected;
            const string error = replay.Step(bar, first, second, rejected);
            if (!error.empty()) {
                std::cerr << error << '\n';
                return 1;
            }
            WriteFill(first);
            WriteFill(second);
            if (!rejected.empty()) std::cout << "R " << bar.opened << ' ' << rejected << '\n';
        }
    }
    if (!std::cin.eof()) return 2;
    if (mode != 0)
        std::cout << "M " << replay.TradeCount() << ' ' << replay.AmbiguousBars() << ' '
                  << replay.Balance() << ' ' << replay.Equity() << ' ' << replay.MaxDrawdown() << ' '
                  << replay.MaxConsecutiveLosses() << ' ' << replay.HasPosition() << '\n';
}
