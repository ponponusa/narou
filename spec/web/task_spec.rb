# frozen_string_literal: true

require "spec_helper"
require "lib/web/workers/task"

describe Narou::Task do
  describe "#initialize" do
    it "creates a task with valid parameters" do
      task = Narou::Task.new(
        type: :download,
        novel_id: 1,
        novel_title: "Test Novel",
        novel_author: "Test Author"
      )

      expect(task.type).to eq(:download)
      expect(task.novel_id).to eq(1)
      expect(task.novel_title).to eq("Test Novel")
      expect(task.novel_author).to eq("Test Author")
      expect(task.status).to eq(:queued)
      expect(task.id).not_to be_nil
    end

    it "raises error for invalid task type" do
      expect {
        Narou::Task.new(type: :invalid)
      }.to raise_error(ArgumentError, /Invalid task type/)
    end
  end

  describe "#start!" do
    it "changes status to running" do
      task = Narou::Task.new(type: :download)
      task.start!

      expect(task.status).to eq(:running)
      expect(task.started_at).not_to be_nil
    end

    it "raises error if already started" do
      task = Narou::Task.new(type: :download)
      task.start!

      expect {
        task.start!
      }.to raise_error("Task already started")
    end
  end

  describe "#complete!" do
    it "changes status to completed" do
      task = Narou::Task.new(type: :download)
      task.start!
      task.complete!

      expect(task.status).to eq(:completed)
      expect(task.completed_at).not_to be_nil
      expect(task.error).to be_nil
    end
  end

  describe "#fail!" do
    it "changes status to failed with error message" do
      task = Narou::Task.new(type: :download)
      task.start!

      error = StandardError.new("Test error")
      task.fail!("Download failed", error)

      expect(task.status).to eq(:failed)
      expect(task.message).to eq("Download failed")
      expect(task.error).not_to be_nil
      expect(task.error[:message]).to eq("Download failed")
    end
  end

  describe "#cancel!" do
    it "changes status to canceled" do
      task = Narou::Task.new(type: :download)
      task.cancel!

      expect(task.status).to eq(:canceled)
      expect(task.message).to eq("キャンセルされました")
    end
  end

  describe "#retryable?" do
    it "returns false when not failed" do
      task = Narou::Task.new(type: :download, max_retries: 3)
      expect(task.retryable?).to be false
    end

    it "returns true when failed and retries available" do
      task = Narou::Task.new(type: :download, max_retries: 3)
      task.start!
      task.fail!("Test error")

      expect(task.retryable?).to be true
    end

    it "returns false when max retries reached" do
      task = Narou::Task.new(type: :download, max_retries: 1)
      task.start!
      task.fail!("Test error")
      task.retry!
      task.start!
      task.fail!("Test error again")

      expect(task.retryable?).to be false
    end
  end

  describe "#retry!" do
    it "resets task for retry" do
      task = Narou::Task.new(type: :download, max_retries: 3)
      task.start!
      task.fail!("Test error")

      task.retry!

      expect(task.status).to eq(:queued)
      expect(task.retry_count).to eq(1)
      expect(task.error).to be_nil
    end
  end

  describe "#to_h" do
    it "returns hash representation of task" do
      task = Narou::Task.new(
        type: :download,
        novel_id: 1,
        novel_title: "Test Novel",
        novel_author: "Test Author"
      )

      hash = task.to_h

      expect(hash[:type]).to eq("download")
      expect(hash[:novel_id]).to eq(1)
      expect(hash[:novel_title]).to eq("Test Novel")
      expect(hash[:status]).to eq("queued")
      expect(hash[:id]).not_to be_nil
    end
  end

  describe "#elapsed_time" do
    it "returns 0 when not started" do
      task = Narou::Task.new(type: :download)
      expect(task.elapsed_time).to eq(0)
    end

    it "returns elapsed time when running" do
      task = Narou::Task.new(type: :download)
      task.start!
      sleep 0.1

      expect(task.elapsed_time).to be > 0
    end

    it "returns total time when completed" do
      task = Narou::Task.new(type: :download)
      task.start!
      sleep 0.1
      task.complete!

      elapsed = task.elapsed_time
      sleep 0.1

      # 完了後は時間が進まない
      expect(task.elapsed_time).to eq(elapsed)
    end
  end

  describe "#update_progress" do
    it "updates progress percentage" do
      task = Narou::Task.new(type: :download)
      task.update_progress(50.0, "50% complete")

      expect(task.progress).to eq(50.0)
      expect(task.message).to eq("50% complete")
    end

    it "clamps progress to 0-100 range" do
      task = Narou::Task.new(type: :download)
      task.update_progress(-10.0)
      expect(task.progress).to eq(0.0)

      task.update_progress(150.0)
      expect(task.progress).to eq(100.0)
    end
  end

  describe "#set_total_steps and #advance_step" do
    it "tracks progress by steps" do
      task = Narou::Task.new(type: :download)
      task.set_total_steps(10)

      expect(task.total_steps).to eq(10)
      expect(task.current_step).to eq(0)
      expect(task.progress).to eq(0.0)

      task.advance_step("Step 1")
      expect(task.current_step).to eq(1)
      expect(task.progress).to eq(10.0)
      expect(task.message).to eq("Step 1")

      task.advance_step("Step 2")
      expect(task.current_step).to eq(2)
      expect(task.progress).to eq(20.0)
    end
  end
end
