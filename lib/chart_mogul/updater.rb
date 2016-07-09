# BUG NoMethodError: undefined method `prepend' for ChartMogul::Metrics::ARPAs:Class
module ChartMogul
  class Object
  end

  class APIResource < Object
    def self.prepend(*args)
    end
  end
end

require 'chartmogul'

# Enable some logging...
module ChartMogul
  class APIResource
    def self.connection
      @connection ||= Faraday.new(url: ChartMogul::API_BASE) do |faraday|
        faraday.use Faraday::Request::BasicAuthentication, ChartMogul.account_token, ChartMogul.secret_key
        faraday.use Faraday::Response::RaiseError
        faraday.use Faraday::Adapter::NetHttp

        faraday.response :logger
      end
    end
  end
end

require 'monetize'
require 'thread_safe'

module Killbill::Chartmogul
  class Updater

    def initialize(config, kb_apis, logger)
      # TODO Won't work well in multi-tenant mode
      ::ChartMogul.account_token = config[:account_token]
      ::ChartMogul.secret_key = config[:secret_key]

      @kb_apis = kb_apis
      @logger = logger

      @plan_cache = ThreadSafe::Cache.new
    end

    def update(event_type, object_id, account_id, tenant_id)
      # Listen to invoice payment events
      if event_type == :INVOICE_PAYMENT_SUCCESS || event_type == :INVOICE_PAYMENT_FAILED
        first_or_create_invoice(object_id, account_id, tenant_id)
      end

      # TODO future work:
      # * Subscription events (cancellation)
      # * Refund events
      # * Tags and custom fields events
    end

    # For testing
    #private

    # TODO Should probably be configurable on a per tenant basis
    def first_or_create_datasource(name = 'killbill')
      sources = ::ChartMogul::Import::DataSource.all
      ds = sources.find { |ds| ds.name == name }

      ds || ::ChartMogul::Import::DataSource.create!(:name => name)
    end

    def first_or_create_customer(kb_account, ds = first_or_create_datasource)
      customer = ::ChartMogul::Import::Customer.all(:page => 1,
                                                    :per_page => 1,
                                                    :data_source_uuid => ds.uuid,
                                                    :external_id => kb_account.external_key).first

      customer || ::ChartMogul::Import::Customer.create!(:data_source_uuid => ds.uuid,
                                                         :external_id => kb_account.external_key,
                                                         :name => kb_account.name,
                                                         :email => kb_account.email,
                                                         :company => kb_account.company_name,
                                                         :country => kb_account.country,
                                                         :state => kb_account.state_or_province,
                                                         :city => kb_account.city,
                                                         :zip => kb_account.postal_code)
    end

    def first_or_create_plan(kb_plan_phase, ds = first_or_create_datasource)
      return @plan_cache[kb_plan_phase.name] unless @plan_cache[kb_plan_phase.name].nil?

      if kb_plan_phase.phase_type != :EVERGREEN
        # TODO It doesn't look like there is support for trials, etc.
        return nil
      end

      if kb_plan_phase.recurring.nil?
        # TODO It doesn't look like there is support for non-recurring phases
        return nil
      end

      interval_count = nil
      interval_unit = nil
      case kb_plan_phase.recurring.billing_period
        when :DAILY
          interval_count = 1
          interval_unit = 'day'
        when :WEEKLY
          interval_count = 7
          interval_unit = 'day'
        when :BIWEEKLY
          interval_count = 14
          interval_unit = 'day'
        when :THIRTY_DAYS
          interval_count = 30
          interval_unit = 'day'
        when :MONTHLY
          interval_count = 1
          interval_unit = 'month'
        when :QUARTERLY
          interval_count = 3
          interval_unit = 'month'
        when :BIANNUAL
          interval_count = 6
          interval_unit = 'month'
        when :ANNUAL
          interval_count = 1
          interval_unit = 'year'
        when :BIENNIAL
          interval_count = 2
          interval_unit = 'year'
        else
          return nil
      end

      plan = ::ChartMogul::Import::Plan.all(:page => 1,
                                            :per_page => 1,
                                            :data_source_uuid => ds.uuid,
                                            :external_id => kb_plan_phase.name).first

      @plan_cache[kb_plan_phase.name] = plan || ::ChartMogul::Import::Plan.create!(:data_source_uuid => ds.uuid,
                                                                                   :external_id => kb_plan_phase.name,
                                                                                   :name => kb_plan_phase.name,
                                                                                   :interval_count => interval_count,
                                                                                   :interval_unit => interval_unit)
      @plan_cache[kb_plan_phase.name]
    end

    def first_or_create_invoice(kb_invoice_id, kb_account_id, kb_tenant_id, ds = first_or_create_datasource)
      kb_context = @kb_apis.create_context(kb_tenant_id)
      # Note that the get_invoice API won't populate the payments
      kb_invoices = @kb_apis.invoice_user_api.get_invoices_by_account(kb_account_id, true, kb_context)
      kb_invoice = kb_invoices.find { |kb_invoice| kb_invoice.id == kb_invoice_id }
      return if kb_invoice.nil?

      kb_account = @kb_apis.account_user_api.get_account_by_id(kb_invoice.account_id, kb_context)
      customer = first_or_create_customer(kb_account, ds)

      # TODO There is no support for adjustments
      invoices = customer.invoices
      return if invoices.find { |invoice| invoice.external_id == kb_invoice.id }

      line_items = []
      transactions = []

      kb_invoice.invoice_items.each do |kb_invoice_item|
        amount_in_cents = kb_invoice_item.amount.nil? ? nil : ::Monetize.from_numeric(kb_invoice_item.amount, kb_invoice_item.currency).cents.to_i

        if kb_invoice_item.invoice_item_type == :RECURRING
          kb_static_catalog = @kb_apis.catalog_user_api.get_current_catalog('unused', kb_context)
          kb_plan_phase = find_current_phase(kb_invoice_item.phase_name, kb_static_catalog)
          plan = kb_plan_phase.nil? ? nil : first_or_create_plan(kb_plan_phase, ds)
          next if plan.nil?

          rate_in_cents = kb_invoice_item.rate.nil? ? nil : ::Monetize.from_numeric(kb_invoice_item.rate, kb_invoice_item.currency).cents.to_i
          prorated = amount_in_cents != rate_in_cents

          line_items << ::ChartMogul::Import::LineItems::Subscription.new(:external_id => kb_invoice_item.id,
                                                                          :plan_uuid => plan.uuid,
                                                                          :subscription_external_id => kb_invoice_item.subscription_id,
                                                                          :service_period_start => kb_invoice_item.start_date,
                                                                          :service_period_end => kb_invoice_item.end_date,
                                                                          :amount_in_cents => amount_in_cents,
                                                                          :prorated => prorated,
                                                                          :quantity => 1,
                                                                          :discount_code => nil,
                                                                          :discount_amount_in_cents => nil,
                                                                          # TODO
                                                                          :tax_amount_in_cents => nil)
        elsif kb_invoice_item.invoice_item_type == :FIXED || kb_invoice_item.invoice_item_type == :EXTERNAL_CHARGE
          line_items << ::ChartMogul::Import::LineItems::OneTime.new(:external_id => kb_invoice_item.id,
                                                                     :description => kb_invoice_item.description,
                                                                     :amount_in_cents => amount_in_cents,
                                                                     :quantity => 1,
                                                                     :discount_code => nil,
                                                                     :discount_amount_in_cents => nil,
                                                                     # TODO
                                                                     :tax_amount_in_cents => nil)
        else
          # TODO It seems that other types aren't supported
        end
      end

      kb_invoice.payments.each do |kb_invoice_payment|
        if kb_invoice_payment.type == :ATTEMPT
          transactions << ::ChartMogul::Import::Transactions::Payment.new(:external_id => kb_invoice_payment.id,
                                                                          :date => kb_invoice_payment.payment_date,
                                                                          :result => kb_invoice_payment.is_success)
        elsif kb_invoice_payment.type == :REFUND
          transactions << ::ChartMogul::Import::Transactions::Refund.new(:external_id => kb_invoice_payment.id,
                                                                         :date => kb_invoice_payment.payment_date,
                                                                         :result => kb_invoice_payment.is_success)
        else
          # TODO There is no support for chargebacks
        end
      end

      return if line_items.empty?

      invoice = ::ChartMogul::Import::Invoice.new(:external_id => kb_invoice.id,
                                                  :date => kb_invoice.invoice_date,
                                                  :currency => kb_invoice.currency.to_s,
                                                  :due_date => kb_invoice.invoice_date,
                                                  :line_items => line_items,
                                                  :transactions => transactions)

      begin
        ::ChartMogul::Import::CustomerInvoices.create!(:customer_uuid => customer.uuid,
                                                       :invoices => [invoice])
      rescue => e
        @logger.warn "Unable to create invoice #{invoice.inspect}: #{e.message}\n#{e.backtrace.join("\n")}"
      end
    end

    def find_current_phase(phase_name, catalog)
      plan_name = nil
      %w(trial discount fixedterm evergreen).each do |type|
        if phase_name.end_with?(type)
          plan_name = phase_name[0..phase_name.size - type.size - 2]
          break
        end
      end
      return nil if plan_name.nil?

      kb_plan = catalog.current_plans.find { |plan| plan.name == plan_name }
      return nil if kb_plan.nil?

      kb_plan.all_phases.find { |phase| phase.name == phase_name }
    end
  end
end
