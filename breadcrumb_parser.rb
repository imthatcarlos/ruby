# This class parses data received from the Breadcrumb API, and hands it off to a Database class that 
# is in charge of saving to the db.
module Import
  class BreadcrumbParser

    def initialize
      @mappings            = Mapping.where(source: "breadcrumb").inject({}) { |memo, m| memo[m.source_id] = m.entity_id ; memo }
      @parent_category_ids = Category.all.inject({}) { |memo, c| memo[c.id] = c.parent_category_id ; memo }
      @category_ids        = Category.all.inject({}) { |memo, c| memo[c.name] = c.id ; memo }
    end

    def handle_data(data, location_id, date)
      return if data.empty?

      data.each do |check|
        next if check["status"] != "Closed" || check["payments"].nil?

        if check["items"].present?
          order_date = date || Time.zone.parse(check["items"].first["date"]).to_date
        else
          order_date = date || Time.zone.parse(check["open_time"]).to_date
        end

        comps      = calculate_comps_total(check) || 0
        net        = Float(check["sub_total"] || 0)
        gross      = Float(check["total"] || 0)
        gross     += comps

        this_order = Database.create_order({ location_id: location_id,
                                              customer_id: nil,
                                              order_date: order_date,
                                              total_net: net,
                                              total_gross: gross,
                                              api_order_id: check["id"],
                                              source: "breadcrumb" })

        return if !this_order.valid?

        check["items"].each do |item|
          mapping = @mappings[item["category_id"]]

          if mapping.present?
            category_id     = mapping
            top_category_id = @parent_category_ids[category_id]
          else
            category_id     = @category_ids[category_mappings[item["category_id"]]]
            top_category_id = category_id
          end

          product = Database.find_or_create_product(item["name"],
                                                    item["name"],
                                                    category_id,
                                                    Float(item["price"]))
          if mapping.nil?
            Database.create_mapping({ source: "breadcrumb",
                                      source_id: item["category_id"],
                                      entity_type: "category",
                                      entity_id: product.category_id })
          end

          Database.create_orderitem({ product_id: product.id,
                                      quantity: item["quantity"],
                                      order_id: this_order.id,
                                      top_category_id: top_category_id })
        end
      end
    end

    private

    def calculate_comps_total(check)
      return 0 unless check["voidcomp"]

      product_total = calculate_product_total(check) || 0

      if check["voidcomp"]["type"] == "comp percent"
        percent  = Float(check["voidcomp"]["value"] || 0)
        discount = (product_total * percent) / 100
      else
        discount = Float(check["voidcomp"]["value"] || 0)
      end

      discount
    end

    def calculate_product_total(check)
      check["items"].map { |item| Float(item["price"] || 0) }.reduce(&:+)
    end

    def category_mappings
      @category_mappings ||= JSON.load(File.read("./breadcrumb_data/mappings.json"))
    end

  end
end