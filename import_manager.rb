# This class manages data import from 3 APIs: Square, Breadcrumb, and Shopify
module Import
  class Manager

    # Given a location id and the date, choose the appropriate API client, fetch data, and parse it.
    def import(loc_id, date)
      loc = Location.find(loc_id)

      case loc.source
      when "breadcrumb"
        client = Breadcrumb::Client.new(api_key: ENV["BREADCRUMB_API_KEY"],
                                        username: loc.breadcrumb_username,
                                        password: loc.breadcrumb_password)
        data  = client.fetch_data(date)
        ParserBreadcrumb.new.handle_data(data, loc_id, date) if data.present?

      when "square"
        client = Square::Client.new(api_key: ENV["SQUARE_API_KEY"])

        if Location.find(loc_id).name == "Beverly_Hills"
          date = date.in_time_zone('Pacific Time (US & Canada)').beginning_of_day
        end

        data = client.fetch_data(loc.square_merchant_id, date)
        ParserSquare.new.handle_data(data, loc.id) if data.present?

      when "shopify"
        client = Shopify::Client.new(loc.name)
        data = client.fetch_data({ financial_status: "paid", created_at_min: date, created_at_max: (date + 1) })
        ParserShopify.new(loc.name).handle_data(data, loc.id) if data.present?
      else
        fail "Invalid source"
      end
    end

    def import_historical(loc_id)
      loc = Location.find(loc_id)

      case loc.source
      when "breadcrumb"
        import_historical_breadcrumb(loc.breadcrumb_username,
                                      loc.breadcrumb_password,
                                      loc.id,
                                      loc.name)
      when "square"
        import_historical_square(loc.square_merchant_id, loc.id)
      when "shopify"
        import_historical_shopify(loc_id)
      else
        fail "Invalid source"
      end
    end

    # Breadbcrumb requires the folder 'breadcrumb_data' in the root directory for initial data import
    def import_historical_breadcrumb(username, password, loc_id, loc_name)
      Dir["#{Rails.root}/breadcrumb_data/#{loc_name}/*.json"].sort.each do |file|
        data = JSON.parse(File.read(File.open(file, "r")))
        ParserBreadcrumb.new.handle_data(data, loc_id, nil)
      end
    end

    def import_historical_square(merchant_id, loc_id)
      puts "fetching square data"
      client = Square::Client.new(api_key: ENV["SQUARE_API_KEY"])
      data = client.payments(merchant_id, {}).flatten
      puts "importing square data"
      ParserSquare.new().handle_data(data, loc_id)
    end

    def import_historical_shopify(loc_id)
      loc_name = Location.find(loc_id).name
      client = Shopify::Client.new(loc_name)
      parser = ParserShopify.new(loc_name)
      parser.init_product_types

      count = client.orders_count
      pages = count / 50

      1.upto(pages+1) do |page|
        puts "Fetching orders: page #{page}"
        data = client.orders(page)

        puts "processing orders"
        parser.handle_data(data, loc_id)
      end
    end

  end
end