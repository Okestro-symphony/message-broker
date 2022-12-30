%% This Source Code Form is subject to the terms of the Mozilla Public
%% License, v. 2.0. If a copy of the MPL was not distributed with this
%% file, You can obtain one at https://mozilla.org/MPL/2.0/.
%%
%% Copyright (c) 2007-2021 VMware, Inc. or its affiliates.  All rights reserved.
%%

-module(rabbit_prelaunch_logging).

-export([setup/1]).

setup(Context) ->
    _ = rabbit_log_prelaunch:debug(""),
    _ = rabbit_log_prelaunch:debug("== Logging =="),
    ok = set_ERL_CRASH_DUMP_envvar(Context),
    ok = configure_lager(Context).

set_ERL_CRASH_DUMP_envvar(#{log_base_dir := LogBaseDir}) ->
    case os:getenv("ERL_CRASH_DUMP") of
        false ->
            ErlCrashDump = filename:join(LogBaseDir, "erl_crash.dump"),
            _ = rabbit_log_prelaunch:debug(
              "Setting $ERL_CRASH_DUMP environment variable to \"~ts\"",
              [ErlCrashDump]),
            os:putenv("ERL_CRASH_DUMP", ErlCrashDump),
            ok;
        ErlCrashDump ->
            _ = rabbit_log_prelaunch:debug(
              "$ERL_CRASH_DUMP environment variable already set to \"~ts\"",
              [ErlCrashDump]),
            ok
    end.

configure_lager(#{log_base_dir := LogBaseDir,
                  main_log_file := MainLog,
                  upgrade_log_file := UpgradeLog} = Context) ->
    {SaslErrorLogger,
     MainLagerHandler,
     UpgradeLagerHandler} = case MainLog of
                                "-" ->
                                    %% Log to STDOUT.
                                    _ = rabbit_log_prelaunch:debug(
                                      "Logging to stdout"),
                                    {tty,
                                     tty,
                                     tty};
                                _ ->
                                    _ = rabbit_log_prelaunch:debug(
                                      "Logging to:"),
                                    [_ = rabbit_log_prelaunch:debug(
                                       "  - ~ts", [Log])
                                     || Log <- [MainLog, UpgradeLog]],
                                    %% Log to file.
                                    {false,
                                     MainLog,
                                     UpgradeLog}
                            end,

    ok = application:set_env(lager, crash_log, "log/crash.log"),

    Fun = fun({App, Var, Value}) ->
                  case application:get_env(App, Var) of
                      undefined -> ok = application:set_env(App, Var, Value);
                      _         -> ok
                  end
          end,
    Vars = [{sasl, sasl_error_logger, SaslErrorLogger},
            {rabbit, lager_log_root, LogBaseDir},
            {rabbit, lager_default_file, MainLagerHandler},
            {rabbit, lager_upgrade_file, UpgradeLagerHandler}],
    lists:foreach(Fun, Vars),

    ok = rabbit_lager:start_logger(),

    ok = rabbit_prelaunch_early_logging:setup_early_logging(Context, false).
