# frozen_string_literal: true

require "spec_helper"
require "lib/web/workers/web_worker"
require "lib/web/workers/convert_worker"
require "lib/web/workers/task"

RSpec.describe Narou::ConvertWorker do
  let(:worker) { Narou::ConvertWorker.instance }

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

    # AppServerのモック化（ConvertWorkerがAppServerに依存しているため）
    app_server_class = class_double("Narou::AppServer")
    stub_const("Narou::AppServer", app_server_class)
    allow(app_server_class).to receive(:push_server).and_return(nil)

    # WebWorkerのモック化（get_tasks_summaryを呼び出すため）
    allow(Narou::WebWorker).to receive(:get_tasks_summary).and_return({
      current: nil,
      queued: [],
      recent_completed: [],
      recent_failed: []
    })
  end

  after do
    worker.stop if worker.running?
    sleep 0.02
    Thread.report_on_exception = true
  end

  describe ".instance" do
    it "returns singleton instance" do
      expect(Narou::ConvertWorker.instance).to be worker
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
  end

  describe "#push_task_impl" do
    it "accepts only Narou::Task instances" do
      expect {
        worker.push_task_impl("not a task") { }
      }.to raise_error(ArgumentError, /Task must be a Narou::Task/)
    end

    it "increments size when task is pushed" do
      worker.start

      task = Narou::Task.new(type: :convert, novel_id: 1, novel_title: "Test")

      expect {
        worker.push_task_impl(task) { }
      }.to change { worker.size }.by(1)

      worker.stop
    end

    it "returns task id" do
      worker.start

      task = Narou::Task.new(type: :convert, novel_id: 1, novel_title: "Test")
      result = worker.push_task_impl(task) { }

      expect(result).to eq(task.id)

      worker.stop
    end
  end

  describe ".push_task" do
    it "delegates to push_task_impl" do
      worker.start

      task = Narou::Task.new(type: :convert, novel_id: 1, novel_title: "Test")
      result = Narou::ConvertWorker.push_task(task) { }

      expect(result).to eq(task.id)

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
        Narou::ConvertWorker.run
        expect(worker.running?).to be true
        worker.stop
      end
    end

    describe ".stop" do
      it "stops the worker" do
        worker.start
        Narou::ConvertWorker.stop
        expect(worker.running?).to be false
      end
    end

    describe ".canceled?" do
      it "returns false initially" do
        expect(Narou::ConvertWorker.canceled?).to be false
      end
    end

    describe ".get_tasks" do
      it "returns an array" do
        tasks = Narou::ConvertWorker.get_tasks
        expect(tasks).to be_an(Array)
      end
    end

    describe ".get_tasks_summary" do
      it "returns a hash" do
        summary = Narou::ConvertWorker.get_tasks_summary
        expect(summary).to be_a(Hash)
      end
    end

    describe ".get_task" do
      it "returns nil for non-existent task" do
        task = Narou::ConvertWorker.get_task("test-id")
        expect(task).to be_nil
      end
    end

    describe ".cancel_task" do
      it "returns failure for non-existent task" do
        result = Narou::ConvertWorker.cancel_task("test-id")
        expect(result[:success]).to be false
      end
    end
  end

  describe "#get_combined_tasks_summary" do
    it "combines WebWorker and ConvertWorker summaries" do
      allow(Narou::WebWorker).to receive(:get_tasks_summary).and_return({
        current: { id: "web-1", type: "download" },
        queued: [{ id: "web-2", type: "update" }],
        recent_completed: [{ id: "web-3", type: "download", completed_at: "2024-01-01T00:00:00Z" }],
        recent_failed: []
      })

      summary = worker.get_combined_tasks_summary

      expect(summary).to have_key(:current)
      expect(summary).to have_key(:queued)
      expect(summary).to have_key(:recent_completed)
      expect(summary).to have_key(:recent_failed)
      expect(summary).to have_key(:convert_current)
      expect(summary).to have_key(:convert_queued)
    end
  end
end
