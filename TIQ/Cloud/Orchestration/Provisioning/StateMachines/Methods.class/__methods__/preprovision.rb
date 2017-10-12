#
# Description: This method prepares arguments and parameters for orchestration provisioning
#
module ManageIQ
  module Automate
    module Cloud
      module Orchestration
        module Provisioning
          module StateMachines
            class PreProvision
              def initialize(handle = $evm)
                @handle = handle
              end
              
              def get_stack_name(stack_name)
                stack = $evm.vmdb(:OrchestrationTemplate).find_by(:name=>stack_name)
                while stack
                  stack_name = stack_name.succ
                  stack = $evm.vmdb(:OrchestrationTemplate).find_by(:name=>stack_name)
                end
                $evm.log(:info, "Stack Name: #{stack_name}")
                stack_name
              end

              def main
                @handle.log("info", "Starting Orchestration Pre-Provisioning")

                service = @handle.root["service_template_provision_task"].try(:destination)

                unless service
                  @handle.log(:error, 'Service is nil')
                  raise 'Service is nil'
                end

                # Through service you can examine the orchestration template, manager (i.e., provider)
                # stack_name, and options to create the stack
                # You can also override these selections through service

                @handle.log("info", "manager = #{service.orchestration_manager.name}" \
                                 "(#{service.orchestration_manager.id})")
                @handle.log("info", "template = #{service.orchestration_template.name}" \
                                 "(#{service.orchestration_template.id}))")
                @handle.log("info", "stack name = #{service.stack_name}")
                # Caution: stack_options may contain passwords.
                # $evm.log("info", "stack options = #{service.stack_options.inspect}")

                # Example how to programmatically modify stack options:
                service.stack_name = get_stack_name(service.stack_name)
                stack_options = service.stack_options
                # stack_options[:disable_rollback] = false
                # stack_options[:timeout_mins] = 2 # this option is provider dependent
                # stack_options[:parameters]['flavor'] = 'm1.small'
                # # Important: set stack_options
                # service.stack_options = stack_options
                $evm.log(:info, "stack_options: #{stack_options[:parameters]}")
              end
            end
          end
        end
      end
    end
  end
end

if __FILE__ == $PROGRAM_NAME
  ManageIQ::Automate::Cloud::Orchestration::Provisioning::StateMachines::PreProvision.new.main
end
