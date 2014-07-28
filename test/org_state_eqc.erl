-module(org_state_eqc).

-ifdef(TEST).
-ifdef(EQC).

-import(ft_test_helper, [id/1, permission/0, maybe_oneof/1]).
-include_lib("eqc/include/eqc_fsm.hrl").
-include_lib("fqc/include/fqc.hrl").

-compile(export_all).

-define(O, ft_org).
%% This is larger then and time we ever get in the size, used for ensure setting data
%% in LWW registers.
-define(BIG_TIME, 1000000000).


name() ->
    oneof([a, b, c, d, e, f, g]).

trigger() ->
    {name(), action()}.

action() ->
    oneof([{grant, role, a, permission()},
           {grant, user, a, permission()},
           {join, role, non_blank_string()},
           {join, org, non_blank_string()}]).
org() ->
    ?SIZED(Size, org(Size)).

org(Size) ->
    ?LAZY(oneof([{call, ?O, new, [id(Size)]} || Size == 0] ++
                    [?LETSHRINK(
                        [O], [org(Size - 1)],
                        oneof([
                               {call, ?O, load, [id(Size), O]},
                               {call, ?O, uuid, [id(Size), non_blank_string(), O]},
                               {call, ?O, name, [id(Size), non_blank_string(), O]},
                               {call, ?O, set_metadata, [id(Size), non_blank_string(), non_blank_string(), O]},
                               {call, ?O, set_metadata, [id(Size), maybe_oneof(calc_metadata(O)), delete, O]},
                               {call, ?O, add_trigger, [id(Size), non_blank_string(), trigger(), O]},
                               {call, ?O, remove_trigger, [id(Size), maybe_oneof(calc_triggers(O)), O]}

                              ]))
                     || Size > 0])).

calc_metadata({call, _, set_metadata, [_, delete, K, U]}) ->
    lists:delete(K, lists:usort(calc_metadata(U)));
calc_metadata({call, _, set_metadata, [_, I, _K, U]}) ->
    [I | calc_metadata(U)];
calc_metadata({call, _, _, P}) ->
    calc_metadata(lists:last(P));
calc_metadata(_) ->
    [].

calc_triggers({call, _, remove_triggers, [_, I, _, U]}) ->
    lists:delete(I, lists:usort(calc_triggers(U)));
calc_triggers({call, _, add_trigger, [_, I, _K, U]}) ->
    [I | calc_triggers(U)];
calc_triggers({call, _, _, P}) ->
    calc_triggers(lists:last(P));
calc_triggers(_) ->
    [].

r(K, V, U) ->
    lists:keystore(K, 1, U, {K, V}).

model_uuid(N, R) ->
    r(<<"uuid">>, N, R).

model_name(N, R) ->
    r(<<"name">>, N, R).

model_set_metadata(K, V, U) ->
    r(<<"metadata">>, lists:usort(r(K, V, metadata(U))), U).

model_delete_metadata(K, U) ->
    r(<<"metadata">>, lists:keydelete(K, 1, metadata(U)), U).

model_add_trigger(UUID, T, U) ->
    r(<<"triggers">>, lists:usort(r(UUID, ?O:jsonify_trigger(T), triggers(U))), U).

model_remove_trigger(I, U) ->
    r(<<"triggers">>, lists:keydelete(I, 1, triggers(U)), U).


model(R) ->
    ?O:to_json(R).

metadata(U) ->
    {<<"metadata">>, M} = lists:keyfind(<<"metadata">>, 1, U),
    M.

triggers(U) ->
    {<<"triggers">>, M} = lists:keyfind(<<"triggers">>, 1, U),
    M.

prop_name() ->
    ?FORALL({N, R},
            {non_blank_string(), org()},
            begin
                Org = eval(R),
                ?WHENFAIL(io:format(user, "History: ~p~nOrg: ~p~n", [R,Org]),
                          model(?O:name(id(?BIG_TIME), N, Org)) ==
                              model_name(N, model(Org)))
            end).

prop_uuid() ->
    ?FORALL({N, R},
            {non_blank_string(), org()},
            begin
                Org = eval(R),
                ?WHENFAIL(io:format(user, "History: ~p~nOrg: ~p~n", [R, Org]),
                          model(?O:uuid(id(?BIG_TIME), N, Org)) ==
                              model_uuid(N, model(Org)))
            end).

prop_set_metadata() ->
    ?FORALL({K, V, O}, {non_blank_string(), non_blank_string(), org()},
            begin
                Org = eval(O),
                O1 = ?O:set_metadata(id(?BIG_TIME), K, V, Org),
                M1 = model_set_metadata(K, V, model(Org)),
                ?WHENFAIL(io:format(user, "History: ~p~nOrg: ~p~nModel: ~p~n"
                                    "Org': ~p~nModel': ~p~n", [O, Org, model(Org), O1, M1]),
                          model(O1) == M1)
            end).

prop_remove_metadata() ->
    ?FORALL({O, K}, ?LET(O, org(), {O, maybe_oneof(calc_metadata(O))}),
            begin
                Org = eval(O),
                O1 = ?O:set_metadata(id(?BIG_TIME), K, delete, Org),
                M1 = model_delete_metadata(K, model(Org)),
                ?WHENFAIL(io:format(user, "History: ~p~nOrg: ~p~nModel: ~p~n"
                                    "Org': ~p~nModel': ~p~n", [O, Org, model(Org), O1, M1]),
                          model(O1) == M1)
            end).

prop_add_trigger() ->
    ?FORALL({UUID, T, O}, {non_blank_string(), trigger(), org()},
            begin
                Org = eval(O),
                O1 = ?O:add_trigger(id(?BIG_TIME), UUID, T, Org),
                M1 = model_add_trigger(UUID, T, model(Org)),
                ?WHENFAIL(io:format(user, "History: ~p~nOrg: ~p~nModel: ~p~n"
                                    "Org': ~p~nModel': ~p~n", [O, Org, model(Org), O1, M1]),
                          model(O1) == M1)
            end).
prop_remove_trigger() ->
    ?FORALL({O, T}, ?LET(O, org(), {O, maybe_oneof(calc_triggers(O))}),
            begin
                Org = eval(O),
                O1 = ?O:remove_trigger(id(?BIG_TIME), T, Org),
                M1 = model_remove_trigger(T, model(Org)),
                ?WHENFAIL(io:format(user, "History: ~p~nOrg: ~p~nModel: ~p~n"
                                    "Org': ~p~nModel': ~p~n", [O, Org, model(Org), O1, M1]),
                          model(O1) == M1)
            end).

-endif.
-endif.
