#
# Description: This method updates the service provision status.
# Required inputs: status
#
module ManageIQ
  module Automate
    module Cloud
      module Orchestration
        module Provisioning
          module StateMachines
            class UpdateServiceProvisionStatus
              def initialize(handle = $evm)
                @handle = handle
              end

              def main
                prov = @handle.root['service_template_provision_task']

                if prov.nil?
                  @handle.log(:error, "Service Template Provision Task not provided")
                  raise "Service Template Provision Task not provided"
                end

                updated_message = update_status_message(prov, @handle.inputs['status'])

                if @handle.root['ae_result'] == "error"
                  @handle.create_notification(:level   => "error",
                                              :subject => prov.miq_request,
                                              :message => "Instance Provision Error: #{updated_message}")
                  @handle.log(:error, "Instance Provision Error: #{updated_message}")

                  if prov.destination.orchestration_manager.type == "ManageIQ::Providers::Azure::CloudManager"
                    #prov.miq_request.user_message = @handle.root['ae_reason']
                    #prov.miq_request.user_message = @handle.root['ae_reason'].truncate(255) if @handle.root['ae_reason'].respond_to?(:truncate)
                    prov.miq_request.user_message = get_inner_error(prov.destination)
                  end
                end
              end

              private

              def update_status_message(prov, status)
                updated_message  = "Server [#{@handle.root['miq_server'].name}] "
                updated_message += "Service [#{prov.destination.name}] "
                updated_message += "Step [#{@handle.root['ae_state']}] "
                updated_message += "Status [#{status}] "
                updated_message += "Message [#{prov.message}] "
                updated_message += "Current Retry Number [#{@handle.root['ae_state_retries']}]"\
                                    if @handle.root['ae_result'] == 'retry'
                prov.miq_request.user_message = updated_message
                prov.message = status
              end
              
              def get_inner_error(service)
                require 'azure-armrest'

                conf = Azure::Armrest::ArmrestService.configure(
                  :client_id        => service.orchestration_manager.authentication_userid,
                  :client_key       => service.orchestration_manager.authentication_password,
                  :tenant_id        => service.orchestration_manager.uid_ems,
                  :subscription_id  => service.orchestration_manager.subscription
                )

                stack_name      = service.stack_name
                resource_group  = service.options[:create_options][:resource_group]
                @handle.log(:info, "Stack: #{stack_name}, Resource Group: #{resource_group}")

                event_service   = Azure::Armrest::Insights::EventService.new(conf)
                date            = (Time.now - 15.minutes).httpdate
                filter          = "eventTimestamp ge #{date} and resourceGroupName eq #{resource_group}"
                select          = 'eventTimestamp, resourceGroupName, Properties'
                events          = event_service.list(:filter => filter, :select => select, :all => true)

                request_message = nil
                events.each do |event|
                  code, message = nil
                  @handle.log(:debug, "event_timestamp: #{event.event_timestamp}") if event.respond_to?(:event_timestamp)

                  if event.respond_to?(:properties)
                    if event.properties.respond_to?(:status_code)
                      @handle.log(:debug, "status_code: #{event.properties.status_code}")

                      if event.properties.respond_to?(:status_message)
                        @handle.log(:debug, "status_message: #{event.properties.status_message}")

                        case event.properties.status_code.downcase
                        when 'conflict'
                          status_message  = JSON.parse(event.properties.status_message)
                          @handle.log(:error, "status_message: #{status_message}")

                          code    = status_message['Code']
                          message = status_message['Message'].gsub(/[^a-zA-Z0-9\-\s],/, '')

                          request_message  = "#{code}: #{message}"
                          break

                        when 'badrequest'
                          status_message  = JSON.parse(event.properties.status_message)
                          @handle.log(:error, "status_message: #{status_message}")

                          unless status_message['error'].nil?
                            if status_message['error']['details'].blank?
                              code    = status_message['error']['code']
                              message = status_message['error']['message']

                            elsif status_message['error']['details'].empty?
                              code    = status_message['error']['code']
                              message = status_message['error']['message']

                            else
                              code    = status_message['error']['details'][0]['code']
                              message = status_message['error']['details'][0]['message']
                            end
                            message = message.gsub(/[^a-zA-Z0-9\-\s],/, '')

                            request_message  = "#{code}: #{message}"
                            break
                          end

                        else
                          @handle.log(:debug, "Ignoring status_code #{event.properties.status_code}")
                        end

                      else
                        @handle.log(:debug, "Ignoring empty status_message")
                      end

                    end
                  end
                end
                
                if request_message.nil?
                  #request_message = @handle.root['ae_reason']
                  request_message = "Stack error detected but no stack error events found, retrying in a few moments."
                  @handle.log(:warn, request_message)
                  
                  @handle.root['ae_result']         = 'retry'
                  @handle.root['ae_retry_interval'] = '15.seconds'
                end
               	request_message = request_message.truncate(255) if request_message.respond_to?(:truncate)
                request_message
              end

            end
          end
        end
      end
    end
  end
end

if __FILE__ == $PROGRAM_NAME
  ManageIQ::Automate::Cloud::Orchestration::Provisioning::
    StateMachines::UpdateServiceProvisionStatus.new.main
end
