# frozen_string_literal: true

require "rails_helper"

module Worker

  describe Process do
    include ProcessHelpers

    describe "running script/worker.rb" do
      # The worker is another process, so what it writes is only visible, and
      # can only be removed, outside of a test transaction.
      self.use_transactional_tests = false

      let(:health_server_port) { free_port }
      let(:task_names) { described_class::TASKS.map(&:to_s) }

      def remove_worker_records
        ScheduledTask.where(name: task_names).delete_all
        WorkerRole.where(role: "tasks").delete_all
      end

      before { remove_worker_records }
      after { remove_worker_records }

      it "boots, acquires the tasks role, schedules every task and shuts down on TERM" do
        run_script("script/worker.rb", { "HEALTH_SERVER_PORT" => health_server_port }) do |pid, output|
          response = health_check(health_server_port)
          expect(response).to start_with("HTTP/1.1 200 OK")
          expect(response).to end_with("OK")

          wait_until { ScheduledTask.where(name: task_names).count == task_names.size }
          expect(ScheduledTask.where(name: task_names).pluck(:next_run_after)).to all(be > Time.current)
          expect(WorkerRole.where(role: "tasks").count).to eq 1

          status = terminate_process(pid)
          expect(status.exitstatus).to eq 0
          expect(output.read).to include("Received TERM signal. Stopping when able.")
          expect(WorkerRole.where(role: "tasks").count).to eq 0
        end
      end
    end
  end

end
