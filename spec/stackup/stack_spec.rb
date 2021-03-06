require "spec_helper"

describe Stackup::Stack do

  let(:stack) { described_class.new("stack_name") }

  let(:cf_stack) { instance_double("Aws::CloudFormation::Stack") }
  let(:cf_client) { instance_double("Aws::CloudFormation::Client") }

  let(:template) { double(String) }
  let(:parameters) { [] }

  let(:response) { Seahorse::Client::Http::Response.new }

  before do
    allow(Aws::CloudFormation::Client).to receive(:new).and_return(cf_client)
    allow(Aws::CloudFormation::Stack).to receive(:new).and_return(cf_stack)
  end

  describe "#create" do

    subject(:created) { stack.create(template, parameters) }

    before do
      allow(cf_client).to receive(:create_stack).and_return(response)
      allow(stack).to receive(:wait_for_events).and_return(true)
    end

    context "when stack gets successfully created" do
      before do
        allow(response).to receive(:[]).with(:stack_id).and_return("1")
      end
      it { expect(created).to be true }
    end

    context "when stack creation fails" do
      before do
        allow(response).to receive(:[]).with(:stack_id).and_return(nil)
      end
      it { expect(created).to be false }
    end

  end

  describe "#update" do
    subject(:updated) { stack.update(template, parameters) }

    context "when there is no existing stack" do
      before do
        allow(stack).to receive(:deployed?).and_return(false)
      end
      it { expect(updated).to be false }
    end

    context "when there is an existing stack" do
      before do
        allow(stack).to receive(:deployed?).and_return(true)
        allow(cf_client).to receive(:update_stack).and_return(response)
        allow(stack).to receive(:wait_for_events).and_return(true)
      end

      context "in a successfully deployed state" do
        before do
          allow(cf_stack).to receive(:stack_status).and_return("CREATE_COMPLETE")
        end

        context "when stack gets successfully updated" do
          before do
            allow(response).to receive(:[]).with(:stack_id).and_return("1")
          end
          it { expect(updated).to be true }
        end

        context "when stack update fails" do
          before do
            allow(response).to receive(:[]).with(:stack_id).and_return(nil)
          end
          it { expect(updated).to be false }
        end
      end

      context "in a ROLLBACK_COMPLETE state" do
        before do
          allow(cf_stack).to receive(:stack_status).and_return("ROLLBACK_COMPLETE")
        end

        context "when deleting existing stack succeeds" do

          it "deletes the existing stack" do
            allow(response).to receive(:[]).with(:stack_id).and_return("1")
            expect(stack).to receive(:delete).and_return(true)
            stack.update(template, parameters)
          end

          context "when stack gets successfully updated" do
            before do
              allow(response).to receive(:[]).with(:stack_id).and_return("1")
              allow(stack).to receive(:delete).and_return(true)
            end
            it { expect(updated).to be true }
          end

          context "when stack update fails" do
            before do
              allow(response).to receive(:[]).with(:stack_id).and_return("1")
              allow(stack).to receive(:delete).and_return(false)
            end
            it { expect(updated).to be false }
          end
        end

        context "when deleting existing stack fails" do
          before do
            allow(stack).to receive(:delete).and_return(false)
          end
          it { expect(updated).to be false }
        end
      end

      context "in a CREATE_FAILED state" do
        before do
          allow(cf_stack).to receive(:stack_status).and_return("CREATE_FAILED")
        end

        it "does not try to delete the existing stack" do
          allow(response).to receive(:[]).with(:stack_id).and_return("1")
          expect(stack).not_to receive(:delete)
          stack.update(template, parameters)
        end

        it "does not try to delete the existing stack" do
          allow(response).to receive(:[]).with(:stack_id).and_return("1")
          expect(cf_client).not_to receive(:delete_stack)
          expect(updated).to be false
        end
      end
    end
  end

  describe "#deploy" do

    subject(:deploy) { stack.deploy(template, parameters) }

    context "when stack already exists" do

      before do
        allow(stack).to receive(:deployed?).and_return(true)
        allow(cf_stack).to receive(:stack_status).and_return("CREATE_COMPLETE")
        allow(cf_client).to receive(:update_stack).and_return({ stack_id: "stack-name" })
      end

      it "updates the stack" do
        expect(stack).to receive(:update)
        deploy
      end
    end

    context "when stack does not exist" do

      before do
        allow(stack).to receive(:deployed?).and_return(false)
        allow(cf_client).to receive(:create_stack).and_return({ stack_id: "stack-name" })
      end

      it "creates a new stack" do
        expect(stack).to receive(:create)
        deploy
      end
    end
  end


  describe "#delete" do

    subject(:deleted) { stack.delete }

    context "there is no existing stack" do
      before do
        allow(stack).to receive(:deployed?).and_return false
      end

      it { expect(deleted).to be false }

      it "does not try to delete the stack" do
        expect(cf_client).not_to receive(:delete_stack)
      end
    end

    context "there is an existing stack" do
      before do
        allow(stack).to receive(:deployed?).and_return true
        allow(cf_client).to receive(:delete_stack)
      end

      context "deleting the stack succeeds" do
        before do
          allow(stack).to receive(:wait_for_events).and_return("DELETE_COMPLETE")
        end
        it { expect(deleted).to be true }
      end

      context "deleting the stack fails" do
        before do
          allow(stack).to receive(:wait_for_events).and_return("DELETE_FAILED")
        end
        it { expect{ deleted }.to raise_error(Stackup::Stack::UpdateError) }
      end
    end
  end


  context "validate" do
    it "should be valid if cf validate say so" do
      allow(cf_client).to receive(:validate_template).and_return({})
      expect(stack.valid?(template)).to be true
    end

    it "should be invalid if cf validate say so" do
      allow(cf_client).to receive(:validate_template).and_return(:code => "404")
      expect(stack.valid?(template)).to be false
    end

  end

  context "deployed" do
    it "should be true if it is already deployed" do
      allow(cf_stack).to receive(:stack_status).and_return("CREATE_COMPLETE")
      expect(stack.deployed?).to be true
    end

    it "should be false if it is not deployed" do
      allow(cf_stack).to receive(:stack_status).and_raise(Aws::CloudFormation::Errors::ValidationError.new("1", "2"))
      expect(stack.deployed?).to be false
    end
  end
end
