%% This Source Code Form is subject to the terms of the Mozilla Public
%% License, v. 2.0. If a copy of the MPL was not distributed with this
%% file, You can obtain one at https://mozilla.org/MPL/2.0/.
%%
%% Copyright (c) 2007-2021 VMware, Inc. or its affiliates.  All rights reserved.
%%

-record(machine_state, {client_ids = #{},
                        pids = #{},
                        %% add acouple of fields for future extensibility
                        reserved_1,
                        reserved_2}).

