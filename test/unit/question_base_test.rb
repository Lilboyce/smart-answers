
require 'ostruct'
require_relative '../test_helper'

class QuestionBaseTest < ActiveSupport::TestCase
  test "#next_node_for raises an exception when the next node isn't in the list of permitted next nodes" do
    q = SmartAnswer::Question::Base.new(flow = nil, :question_name) {
      permitted_next_nodes = [:allowed_next_node_1, :allowed_next_node_2]
      next_node(permitted: permitted_next_nodes) { :not_allowed_next_node }
    }
    state = SmartAnswer::State.new(q.name)

    expected_message = "Next node (not_allowed_next_node) not in list of permitted next nodes (allowed_next_node_1 and allowed_next_node_2)"
    exception = assert_raises do
      q.next_node_for(state, 'response')
    end
    assert_equal expected_message, exception.message
  end

  test 'permitted next nodes can be supplied to next_node' do
    q = SmartAnswer::Question::Base.new(nil, :example) {
      next_node(permitted: [:done]) do
        :done
      end
    }
    assert_equal [:done], q.permitted_next_nodes
  end

  test "State is carried over on a state transition" do
    q = SmartAnswer::Question::Base.new(nil, :example) {
      next_node :done
    }
    initial_state = SmartAnswer::State.new(q.name)
    initial_state.something_else = "Carried over"
    new_state = q.transition(initial_state, :yes)
    assert_equal "Carried over", new_state.something_else
  end

  test "Next node is taken from next_node_for method" do
    q = SmartAnswer::Question::Base.new(nil, :example) {
      next_node :done
    }
    initial_state = SmartAnswer::State.new(q.name)
    q.stubs(:next_node_for).returns(:done)
    new_state = q.transition(initial_state, :anything)
    assert_equal :done, new_state.current_node
  end

  test "Can define next_node by passing a value" do
    q = SmartAnswer::Question::Base.new(nil, :example) {
      next_node :done
    }
    initial_state = SmartAnswer::State.new(q.name)
    new_state = q.transition(initial_state, :anything)
    assert_equal :done, new_state.current_node
  end

  test "Can define next_node by giving a block, provided that next node is declared" do
    q = SmartAnswer::Question::Base.new(nil, :example) {
      next_node(permitted: [:done_done]) { :done_done }
    }
    initial_state = SmartAnswer::State.new(q.name)
    new_state = q.transition(initial_state, :anything)
    assert_equal :done_done, new_state.current_node
  end

  test "next_node block can refer to state" do
    q = SmartAnswer::Question::Base.new(nil, :example) {
      permitted_next_nodes = [:was_red, :wasnt_red]
      next_node(permitted: permitted_next_nodes) do
        colour == 'red' ? :was_red : :wasnt_red
      end
    }
    initial_state = SmartAnswer::State.new(q.name)
    initial_state.colour = 'red'
    new_state = q.transition(initial_state, 'anything')
    assert_equal :was_red, new_state.current_node
  end

  test "next_node block is passed input" do
    input_was = nil
    q = SmartAnswer::Question::Base.new(nil, :example) {
      next_node(permitted: [:done]) do |input|
        input_was = input
        :done
      end
    }
    initial_state = SmartAnswer::State.new(q.name)
    new_state = q.transition(initial_state, 'something')
    assert_equal 'something', input_was
  end

  test "Input can be saved into the state" do
    q = SmartAnswer::Question::Base.new(nil, :favourite_colour?) do
      save_input_as :colour_preference
      next_node :done
    end
    initial_state = SmartAnswer::State.new(q.name)
    new_state = q.transition(initial_state, :red)
    assert_equal :red, new_state.colour_preference
  end

  test "Input sequence is saved into responses" do
    q = SmartAnswer::Question::Base.new(nil, :favourite_colour?) {
      next_node :done
    }
    initial_state = SmartAnswer::State.new(q.name)
    new_state = q.transition(initial_state, :red)
    assert_equal [:red], new_state.responses
  end

  test "Node path is saved in state" do
    q = SmartAnswer::Question::Base.new(nil, :favourite_colour?)
    q.next_node :done
    initial_state = SmartAnswer::State.new(q.name)
    initial_state.current_node = q.name
    new_state = q.transition(initial_state, :red)
    assert_equal [:favourite_colour?], new_state.path
  end

  test "Can calculate other variables based on input" do
    q = SmartAnswer::Question::Base.new(nil, :favourite_colour?) do
      calculate :complementary_colour do |response|
        response == :red ? :green : :red
      end
      next_node :done
    end
    initial_state = SmartAnswer::State.new(q.name)
    new_state = q.transition(initial_state, :red)
    assert_equal :green, new_state.complementary_colour
    assert new_state.frozen?
  end

  test "Can calculate other variables based on saved input" do
    q = SmartAnswer::Question::Base.new(nil, :favourite_colour?) do
      save_input_as :colour_preference
      calculate :complementary_colour do
        colour_preference == :red ? :green : :red
      end
      next_node :done
    end
    initial_state = SmartAnswer::State.new(q.name)
    new_state = q.transition(initial_state, :red)
    assert_equal :green, new_state.complementary_colour
    assert new_state.frozen?
  end

  test "Can perform next_node_calculation which is evaluated before next_node" do
    q = SmartAnswer::Question::Base.new(nil, :favourite_colour?) do
      next_node_calculation :complementary_colour do |response|
        response == :red ? :green : :red
      end
      next_node_calculation :blah do
        "blah"
      end
      next_node(permitted: [:done]) do
        :done if complementary_colour == :green
      end
    end
    initial_state = SmartAnswer::State.new(q.name)
    new_state = q.transition(initial_state, :red)
    assert_equal :green, new_state.complementary_colour
    assert_equal "blah", new_state.blah
    assert_equal :done, new_state.current_node
  end

  test "error if no conditional transitions found and no fallback" do
    question_name = :example
    responses = [:blue, :red]
    q = SmartAnswer::Question::Base.new(nil, question_name) {
      next_node(permitted: [:skipped]) do
        :skipped if false
      end
    }
    initial_state = SmartAnswer::State.new(q.name)
    initial_state.responses << responses[0]
    error = assert_raises(SmartAnswer::Question::Base::NextNodeUndefined) do
      q.next_node_for(initial_state, responses[1])
    end
    expected_message = "Next node undefined. Node: #{question_name}. Responses: #{responses}"
    assert_equal expected_message, error.message
  end
end
