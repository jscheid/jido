defmodule JidoTest.Agent.Strategy.DirectResultTest do
  use ExUnit.Case, async: true

  alias Jido.Action.Result
  alias Jido.Agent.Directive
  alias Jido.Agent.Strategy.Direct

  # An action that returns {:ok, %Result{data: ..., effects: [...]}}
  defmodule ResultAction do
    @moduledoc false
    use Jido.Action,
      name: "result_action",
      schema: []

    def run(_params, _context) do
      {:ok,
       %Result{
         data: %{processed: true, value: 42},
         effects: []
       }}
    end
  end

  # An action that returns {:ok, %Result{}} with effects (directives)
  defmodule ResultWithEffectsAction do
    @moduledoc false
    use Jido.Action,
      name: "result_with_effects_action",
      schema: []

    def run(_params, _context) do
      signal = %{type: "test.emitted", data: %{}}

      {:ok,
       %Result{
         data: %{triggered: true},
         effects: [Directive.emit(signal)]
       }}
    end
  end

  # An action that returns {:error, reason, effects}
  defmodule ErrorWithEffectsAction do
    @moduledoc false
    use Jido.Action,
      name: "error_with_effects_action",
      schema: []

    def run(_params, _context) do
      signal = %{type: "test.cleanup", data: %{}}
      {:error, "something went wrong", [Directive.emit(signal)]}
    end
  end

  defmodule TestAgent do
    @moduledoc false
    use Jido.Agent,
      name: "direct_result_test_agent",
      strategy: Jido.Agent.Strategy.Direct,
      schema: [
        processed: [type: :boolean, default: false],
        value: [type: :integer, default: 0],
        triggered: [type: :boolean, default: false]
      ]

    def signal_routes(_ctx), do: []
  end

  describe "Result struct handling" do
    test "%Result{} data is applied to agent state" do
      agent = TestAgent.new()
      {updated, directives} = TestAgent.cmd(agent, ResultAction)

      assert updated.state.processed == true
      assert updated.state.value == 42
      assert directives == []
    end

    test "%Result{} with effects — effects are processed as directives" do
      agent = TestAgent.new()
      {updated, directives} = TestAgent.cmd(agent, ResultWithEffectsAction)

      assert updated.state.triggered == true
      assert [%Directive.Emit{}] = directives
    end
  end

  describe "error with effects handling" do
    test "{:error, reason, effects} processes effects and returns error directive" do
      agent = TestAgent.new()
      ctx = %{agent_module: TestAgent, strategy_opts: []}

      instruction = %Jido.Instruction{
        action: ErrorWithEffectsAction,
        params: %{},
        context: %{},
        opts: [timeout: 0]
      }

      {_updated, directives} = Direct.cmd(agent, [instruction], ctx)

      # First directive is the error
      assert [%Directive.Error{} = error_directive | rest] = directives
      assert error_directive.context == :instruction

      # Remaining directives are the effects (emit)
      assert [%Directive.Emit{}] = rest
    end

    test "{:error, reason, effects} with no effects returns only error directive" do
      agent = TestAgent.new()
      ctx = %{agent_module: TestAgent, strategy_opts: []}

      # FailingAction returns {:error, reason} — no effects
      failing_instruction = %Jido.Instruction{
        action: JidoTest.TestActions.FailingAction,
        params: %{reason: "test failure"},
        context: %{},
        opts: [timeout: 0]
      }

      {_updated, directives} = Direct.cmd(agent, [failing_instruction], ctx)

      assert [%Directive.Error{}] = directives
    end
  end

  describe "existing behavior unchanged" do
    test "{:ok, map} result merges into agent state" do
      agent = TestAgent.new()
      ctx = %{agent_module: TestAgent, strategy_opts: []}

      instruction = %Jido.Instruction{
        action: JidoTest.TestActions.BasicAction,
        params: %{value: 99},
        context: %{},
        opts: [timeout: 0]
      }

      {updated, directives} = Direct.cmd(agent, [instruction], ctx)

      assert updated.state.value == 99
      assert directives == []
    end
  end
end
