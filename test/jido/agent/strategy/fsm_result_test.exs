defmodule JidoTest.Agent.Strategy.FSMResultTest do
  use ExUnit.Case, async: true

  @moduletag capture_log: true

  alias Jido.Action.Result
  alias Jido.Agent.{Directive, StateOp}
  alias Jido.Agent.Strategy.State, as: StratState
  alias JidoTest.Support.FSMRuntimeHelper

  defmodule FSMResultTestAgent do
    @moduledoc false
    use Jido.Agent,
      name: "fsm_result_test_agent",
      strategy: Jido.Agent.Strategy.FSM,
      schema: [value: [type: :integer, default: 0]]

    def signal_routes(_ctx), do: []
  end

  # An action that fails but also includes effects
  defmodule ErrorWithEffectsAction do
    @moduledoc false
    use Jido.Action,
      name: "error_with_effects_action",
      schema: []

    alias Jido.Agent.StateOp

    def run(_params, _context) do
      {:error, "intentional failure", [%StateOp.SetState{attrs: %{partial: "applied"}}]}
    end
  end

  # An action that returns a %Result{} struct
  defmodule ResultStructAction do
    @moduledoc false
    use Jido.Action,
      name: "result_struct_action",
      schema: []

    alias Jido.Action.Result
    alias Jido.Agent.StateOp

    def run(_params, _context) do
      {:ok,
       %Result{
         data: %{computed: 42},
         effects: [%StateOp.SetState{attrs: %{flagged: true}}],
         content: []
       }}
    end
  end

  # An action that returns a %Result{} with content parts
  defmodule ResultWithContentAction do
    @moduledoc false
    use Jido.Action,
      name: "result_with_content_action",
      schema: []

    alias Jido.Action.{ContentPart, Result}

    def run(_params, _context) do
      {:ok,
       %Result{
         data: %{rendered: true},
         effects: [],
         content: [ContentPart.text("hello")]
       }}
    end
  end

  defp run_cmd(agent, action) do
    FSMRuntimeHelper.run_cmd(FSMResultTestAgent, agent, action)
  end

  describe "error path with effects" do
    test "applies state ops on error before returning error directive" do
      agent = FSMResultTestAgent.new()
      {updated, directives} = run_cmd(agent, ErrorWithEffectsAction)

      # The effect (SetState) should have been applied despite the error
      assert updated.state.partial == "applied"

      # An error directive should still be returned
      assert [%Directive.Error{context: :instruction}] = directives
    end

    test "stores error in machine state when effects are present" do
      agent = FSMResultTestAgent.new()
      {updated, _directives} = run_cmd(agent, ErrorWithEffectsAction)

      state = StratState.get(updated)
      assert state.machine.error != nil
    end
  end

  describe "%Result{} flowing through the pipeline" do
    test "applies data to agent state" do
      agent = FSMResultTestAgent.new()
      {updated, _directives} = run_cmd(agent, ResultStructAction)

      assert updated.state.computed == 42
    end

    test "processes effects from Result struct" do
      agent = FSMResultTestAgent.new()
      {updated, _directives} = run_cmd(agent, ResultStructAction)

      assert updated.state.flagged == true
    end

    test "returns no error directives on success" do
      agent = FSMResultTestAgent.new()
      {_updated, directives} = run_cmd(agent, ResultStructAction)

      refute Enum.any?(directives, &match?(%Directive.Error{}, &1))
    end

    test "Result with content normalizes content field" do
      agent = FSMResultTestAgent.new()
      {updated, directives} = run_cmd(agent, ResultWithContentAction)

      assert updated.state.rendered == true
      refute Enum.any?(directives, &match?(%Directive.Error{}, &1))
    end

    test "increments processed_count on Result success" do
      agent = FSMResultTestAgent.new()
      {updated, _directives} = run_cmd(agent, ResultStructAction)

      state = StratState.get(updated)
      assert state.machine.processed_count == 1
    end
  end
end
