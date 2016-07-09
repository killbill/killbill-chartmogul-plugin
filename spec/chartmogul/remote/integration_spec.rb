require 'spec_helper'

class FakeJavaTenantUserApi

  attr_accessor :per_tenant_config

  def initialize(per_tenant_config = {})
    @per_tenant_config = per_tenant_config
  end

  def get_tenant_values_for_key(key, context)
    result = @per_tenant_config[context.tenant_id.to_s]
    if result
      return [result]
    end
    nil
  end
end

describe Killbill::Chartmogul::ChartmogulPlugin do

  let(:kb_tenant_id) do
    SecureRandom.uuid
  end

  let(:kb_account) do
    now = Time.now.to_i.to_s
    external_key = now + '-test'
    email = external_key + '@tester.com'

    account = ::Killbill::Plugin::Model::Account.new
    account.id = SecureRandom.uuid
    account.external_key = external_key
    account.email = email
    account.name = "Integration spec #{now}"
    account.currency = :USD

    account
  end

  let(:standard_monthly) do
    phase = ::Killbill::Plugin::Model::PlanPhase.new
    phase.name = 'standard-monthly'
    phase.phase_type = :EVERGREEN
    phase.recurring = ::Killbill::Plugin::Model::Recurring.new
    phase.recurring.billing_period = :MONTHLY
    phase
  end

  let(:standard_annual) do
    phase = ::Killbill::Plugin::Model::PlanPhase.new
    phase.name = 'standard-annual'
    phase.phase_type = :EVERGREEN
    phase.recurring = ::Killbill::Plugin::Model::Recurring.new
    phase.recurring.billing_period = :ANNUAL
    phase
  end

  let(:invoice) do
    invoice = ::Killbill::Plugin::Model::Invoice.new
    invoice.id = SecureRandom.uuid
    invoice.invoice_items = [recurring_item]
    invoice
  end

  let(:recurring_item) do
    item = ::Killbill::Plugin::Model::InvoiceItem.new
    item.id = SecureRandom.uuid
    item.amount = 10
    item.currency = :USD
    item.invoice_item_type = :RECURRING
    item
  end

  before(:each) do
    @plugin = Killbill::Chartmogul::ChartmogulPlugin.new
    @plugin.conf_dir = File.expand_path(File.dirname(__FILE__) + '../../../../')

    logger = Logger.new(STDOUT)
    logger.level = Logger::DEBUG
    @plugin.logger = logger

    tenant_user_api = FakeJavaTenantUserApi.new
    tenant_user_api.per_tenant_config[kb_tenant_id] = {:chartmogul => {:account_token => ENV['ACCOUNT_TOKEN'], :secret_key => ENV['SECRET_KEY']}}.to_yaml

    svcs = {:tenant_user_api => tenant_user_api}
    @plugin.kb_apis = Killbill::Plugin::KillbillApi.new('chartmogul', svcs)

    @plugin.start_plugin
  end

  after(:each) do
    @plugin.stop_plugin
  end

  it 'should be able to create and update data' do
    updater = @plugin.initializer.updater(kb_tenant_id)

    ds = updater.first_or_create_datasource
    ds.uuid.should_not be_nil
    updater.first_or_create_datasource.uuid.should == ds.uuid

    customer = updater.first_or_create_customer(kb_account, ds)
    customer.uuid.should_not be_nil
    customer.external_id.should == kb_account.external_key
    updater.first_or_create_customer(kb_account, ds).uuid.should == customer.uuid

    monthly = updater.first_or_create_plan(standard_monthly, ds)
    monthly.uuid.should_not be_nil
    monthly.external_id.should == 'standard-monthly'
    updater.first_or_create_plan(standard_monthly, ds).uuid.should == monthly.uuid

    yearly = updater.first_or_create_plan(standard_annual, ds)
    yearly.uuid.should_not be_nil
    yearly.external_id.should == 'standard-annual'
    updater.first_or_create_plan(standard_annual, ds).uuid.should == yearly.uuid
  end
end
