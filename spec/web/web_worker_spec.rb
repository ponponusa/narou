# frozen_string_literal: true

require "spec_helper"
require "lib/web/workers/web_worker"
require "lib/web/workers/task"

RSpec.describe Narou::WebWorker do
  let(:worker) { Narou::WebWorker.instance }

  before do
    # スレッドの例外をテストプロセスに伝播させない
    Thread.report_on_exception = false

    worker.stop if worker.running?
    sleep 0.02

    # シングルトンの状態をリセット
    worker.instance_variable_set(:@cancel_signal, false)
    worker.instance_variable_set(:@size, 0)
    worker.instance_variable_set(:@tasks, {})
    worker.instance_variable_set(:@task_history, [])
    worker.instance_variable_set(:@current_task, nil)
    worker.instance_variable_set(:@queue, Queue.new)

    # AppServerのモック化（WebWorkerがAppServerに依存しているため）
    app_server_class = class_double("Narou::AppServer")
    stub_const("Narou::AppServer", app_server_class)
    allow(app_server_class).to receive(:push_server).and_return(nil)
  end

  after do
    worker.stop if worker.running?
    sleep 0.02
    Thread.report_on_exception = true
  end

  describe ".instance" do
    it "returns singleton instance" do
      expect(Narou::WebWorker.instance).to be worker
    end
  end

  describe "#initialize state" do
    it "has expected default values" do
      expect(worker.size).to eq(0)
      expect(worker.running?).to be false
      expect(worker.canceled?).to be false
    end
  end

  describe "#running?" do
    it "returns false when not started" do
      expect(worker.running?).to be false
    end

    it "returns true when started" do
      worker.start
      expect(worker.running?).to be true
      worker.stop
    end
  end

  describe "#start and #stop" do
    it "starts and stops worker thread" do
      worker.start
      expect(worker.running?).to be true

      worker.stop
      expect(worker.running?).to be false
    end

    it "does not start multiple times" do
      worker.start
      thread1 = worker.instance_variable_get(:@worker_thread)

      worker.start
      thread2 = worker.instance_variable_get(:@worker_thread)

      expect(thread1).to be thread2

      worker.stop
    end
  end

  describe "#push" do
    before { worker.start }
    after { worker.stop }

    it "increments size when counting is true" do
      expect {
        worker.push(true) { }
      }.to change { worker.size }.by(1)
    end

    it "does not increment size when counting is false" do
      expect {
        worker.push(false) { }
      }.not_to change { worker.size }
    end

    it "executes pushed block" do
      result = false
      worker.push { result = true }

      # ブロックが実行されるまで待つ
      sleep 0.05

      expect(result).to be true
    end
  end

  describe "#push_task_impl" do
    it "accepts only Narou::Task instances" do
      expect {
        worker.push_task_impl("not a task") { }
      }.to raise_error(ArgumentError, /Task must be a Narou::Task/)
    end

    it "increments size when task is pushed" do
      worker.start

      task = Narou::Task.new(type: :download, novel_id: 1, novel_title: "Test")

      expect {
        worker.push_task_impl(task) { }
      }.to change { worker.size }.by(1)

      worker.stop
    end

    it "returns task id" do
      worker.start

      task = Narou::Task.new(type: :download, novel_id: 1, novel_title: "Test")
      result = worker.push_task_impl(task) { }

      expect(result).to eq(task.id)

      worker.stop
    end
  end

  describe ".push_task" do
    it "delegates to push_task_impl" do
      worker.start

      task = Narou::Task.new(type: :download, novel_id: 1, novel_title: "Test")
      result = Narou::WebWorker.push_task(task) { }

      expect(result).to eq(task.id)

      worker.stop
    end
  end

  describe ".push_as_system_worker" do
    before { worker.start }
    after { worker.stop }

    it "pushes without incrementing count" do
      expect {
        Narou::WebWorker.push_as_system_worker { }
      }.not_to change { worker.size }
    end
  end

  describe "#cancel" do
    before { worker.start }
    after { worker.stop }

    it "sets cancel signal when there are tasks" do
      # cancelはsize > 0 の場合のみ動作する
      worker.instance_variable_set(:@size, 1)
      worker.cancel

      expect(worker.canceled?).to be true
    end

    it "does not set cancel signal when no tasks" do
      worker.cancel

      expect(worker.canceled?).to be false
    end

    it "clears size" do
      worker.instance_variable_set(:@size, 2)

      worker.cancel

      expect(worker.size).to eq(0)
    end
  end

  describe "#canceled?" do
    it "returns false initially" do
      expect(worker.canceled?).to be false
    end

    it "returns true after cancel when there are tasks" do
      worker.start
      worker.instance_variable_set(:@size, 1)
      worker.cancel

      expect(worker.canceled?).to be true

      worker.stop
    end
  end

  describe "#get_tasks_impl" do
    it "returns empty array when no tasks" do
      tasks = worker.get_tasks_impl

      expect(tasks).to be_an(Array)
      expect(tasks).to be_empty
    end
  end

  describe "#get_tasks_summary_impl" do
    it "returns summary with correct structure" do
      summary = worker.get_tasks_summary_impl

      expect(summary).to have_key(:current)
      expect(summary).to have_key(:queued)
      expect(summary).to have_key(:recent_completed)
      expect(summary).to have_key(:recent_failed)
    end
  end

  describe "#get_task_impl" do
    it "returns nil for non-existent task" do
      task = worker.get_task_impl("non-existent-id")
      expect(task).to be_nil
    end
  end

  describe "#cancel_task_impl" do
    it "returns error for non-existent task" do
      result = worker.cancel_task_impl("non-existent-id")

      expect(result[:success]).to be false
      expect(result[:message]).to eq("Task not found")
    end
  end

  describe "class methods" do
    describe ".run" do
      it "starts the worker" do
        Narou::WebWorker.run
        expect(worker.running?).to be true
        worker.stop
      end
    end

    describe ".stop" do
      it "stops the worker" do
        worker.start
        Narou::WebWorker.stop
        expect(worker.running?).to be false
      end
    end

    describe ".cancel" do
      it "cancels the worker when there are tasks" do
        worker.start
        worker.instance_variable_set(:@size, 1)

        Narou::WebWorker.cancel

        expect(worker.canceled?).to be true

        worker.stop
      end
    end

    describe ".canceled?" do
      it "returns false initially" do
        expect(Narou::WebWorker.canceled?).to be false
      end

      it "returns cancellation status when there are tasks" do
        worker.start
        worker.instance_variable_set(:@size, 1)
        Narou::WebWorker.cancel

        expect(Narou::WebWorker.canceled?).to be true

        worker.stop
      end
    end

    describe ".get_tasks" do
      it "returns an array" do
        tasks = Narou::WebWorker.get_tasks
        expect(tasks).to be_an(Array)
      end
    end

    describe ".get_tasks_summary" do
      it "returns a hash" do
        summary = Narou::WebWorker.get_tasks_summary
        expect(summary).to be_a(Hash)
      end
    end

    describe ".get_task" do
      it "returns nil for non-existent task" do
        task = Narou::WebWorker.get_task("test-id")
        expect(task).to be_nil
      end
    end

    describe ".cancel_task" do
      it "returns failure for non-existent task" do
        result = Narou::WebWorker.cancel_task("test-id")
        expect(result[:success]).to be false
      end
    end

  end
end
