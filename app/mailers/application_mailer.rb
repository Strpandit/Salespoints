class ApplicationMailer < ActionMailer::Base
  default from: "SalesPoints <salespointecom@gmail.com>"
  layout "mailer"

  helper_method :format_currency, :format_date, :payment_method_label, :format_address, :format_amount

  helper_method :mailer_banner, :mailer_body_open, :mailer_body_close, :mailer_otp_box,
                :mailer_button, :mailer_notice, :mailer_info_table, :mailer_changes_table,
                :mailer_detail_grid, :mailer_actor_block, :mailer_order_item_row,
                :mailer_order_totals, :mailer_badge

  private

  MAILER_THEMES = {
    info: {
      gradient_to: "#1e3a8a", badge_bg: "rgba(59, 130, 246, 0.2)", badge_border: "#3b82f6", badge_text: "#93c5fd",
      accent: "#1d4ed8", soft_bg: "#eff6ff", soft_border: "#bfdbfe", soft_text: "#1e40af"
    },
    success: {
      gradient_to: "#065f46", badge_bg: "rgba(16, 185, 129, 0.2)", badge_border: "#10b981", badge_text: "#34d399",
      accent: "#059669", soft_bg: "#ecfdf5", soft_border: "#a7f3d0", soft_text: "#065f46"
    },
    danger: {
      gradient_to: "#7f1d1d", badge_bg: "rgba(239, 68, 68, 0.2)", badge_border: "#ef4444", badge_text: "#fca5a5",
      accent: "#dc2626", soft_bg: "#fef2f2", soft_border: "#fecaca", soft_text: "#991b1b"
    },
    warning: {
      gradient_to: "#78350f", badge_bg: "rgba(245, 158, 11, 0.2)", badge_border: "#f59e0b", badge_text: "#fcd34d",
      accent: "#d97706", soft_bg: "#fffbeb", soft_border: "#fde68a", soft_text: "#92400e"
    },
    purple: {
      gradient_to: "#581c87", badge_bg: "rgba(147, 51, 234, 0.2)", badge_border: "#9333ea", badge_text: "#d8b4fe",
      accent: "#7e22ce", soft_bg: "#faf5ff", soft_border: "#e9d5ff", soft_text: "#6b21a8"
    },
    neutral: {
      gradient_to: "#334155", badge_bg: "rgba(148, 163, 184, 0.2)", badge_border: "#94a3b8", badge_text: "#e2e8f0",
      accent: "#475569", soft_bg: "#f8fafc", soft_border: "#e2e8f0", soft_text: "#334155"
    }
  }.freeze

  def mailer_theme(key)
    MAILER_THEMES[key.to_s.to_sym] || MAILER_THEMES[:info]
  end

  def esc(value)
    return value if value.is_a?(ActiveSupport::SafeBuffer)
    ERB::Util.html_escape(value.to_s)
  end

  def mailer_format_value(value)
    case value
    when nil
      "—"
    when true
      "Yes"
    when false
      "No"
    when String, Symbol
      str = value.to_s.strip
      if (str.start_with?("[") && str.end_with?("]")) || (str.start_with?("{") && str.end_with?("}"))
        begin
          parsed = JSON.parse(str)
          return mailer_format_value(parsed)
        rescue JSON::ParserError
          # not json, proceed
        end
      end

      if str.include?("\t")
        parts = str.split("\t", 2)
        "#{parts[0].strip}: #{parts[1].strip}"
      else
        str.presence || "—"
      end
    when Array
      formatted_items = value.compact.map do |item|
        mailer_format_value(item)
      end.reject { |v| v == "—" || v.blank? }

      return "—" if formatted_items.empty?

      formatted_items.join("\n").presence || "—"
    when Hash
      formatted = value.map do |k, v|
        formatted_val = mailer_format_value(v)
        next if formatted_val == "—"
        "#{k.to_s.humanize}: #{formatted_val}"
      end.compact.reject(&:blank?)
      formatted.join("\n").presence || "—"
    when Time, DateTime, ActiveSupport::TimeWithZone
      format_date(value)
    when Date
      value.strftime("%d %B, %Y")
    else
      value.to_s.presence || "—"
    end
  end

  def mailer_banner(title:, subtitle: nil, badge: nil, theme: :info)
    t = mailer_theme(theme)
    badge_html = if badge.present?
      <<~HTML
        <table role="presentation" cellpadding="0" cellspacing="0" border="0" style="margin-bottom: 12px;">
          <tr>
            <td style="background-color: #{t[:badge_bg]}; border: 1px solid #{t[:badge_border]}; border-radius: 20px; padding: 4px 14px; font-size: 11px; font-weight: 700; color: #{t[:badge_text]}; text-transform: uppercase; letter-spacing: 1px;">
              #{esc(badge)}
            </td>
          </tr>
        </table>
      HTML
    else
      ""
    end

    subtitle_html = subtitle.present? ? %(<p style="margin: 8px 0 0 0; font-size: 14px; color: #cbd5e1; line-height: 1.5;">#{esc(subtitle)}</p>) : ""

    <<~HTML.html_safe
      <table role="presentation" width="100%" cellpadding="0" cellspacing="0" border="0" style="background: linear-gradient(135deg, #0f172a 0%, #{t[:gradient_to]} 100%); background-color: #0f172a; padding: 36px 28px; text-align: center;">
        <tr>
          <td align="center">
            #{badge_html}
            <h1 style="margin: 0; font-size: 24px; font-weight: 800; color: #ffffff; letter-spacing: -0.5px; line-height: 1.3;">
              #{esc(title)}
            </h1>
            #{subtitle_html}
          </td>
        </tr>
      </table>
    HTML
  end

  def mailer_body_open
    %(<table role="presentation" width="100%" cellpadding="0" cellspacing="0" border="0" style="background-color: #ffffff;"><tr><td style="padding: 32px 28px;">).html_safe
  end

  def mailer_body_close
    "</td></tr></table>".html_safe
  end

  def mailer_badge(text, theme: :info)
    t = mailer_theme(theme)
    %(<span style="display:inline-block; background-color: #{t[:soft_bg]}; color: #{t[:soft_text]}; border: 1px solid #{t[:soft_border]}; border-radius: 20px; padding: 4px 12px; font-size: 11px; font-weight: 700; text-transform: uppercase; letter-spacing: 0.5px;">#{esc(text)}</span>).html_safe
  end

  def mailer_otp_box(code:, label: "One-Time Password", expires_in: nil, theme: :info)
    t = mailer_theme(theme)
    expiry_html = expires_in.present? ? %(<p style="margin: 8px 0 0 0; font-size: 12px; color: #64748b; font-weight: 600;">&#9202; Valid for #{esc(expires_in)}</p>) : ""

    <<~HTML.html_safe
      <table role="presentation" width="100%" cellpadding="0" cellspacing="0" border="0" style="background-color: #{t[:soft_bg]}; border: 2px dashed #{t[:soft_border]}; border-radius: 12px; margin: 20px 0;">
        <tr>
          <td align="center" style="padding: 24px 16px;">
            <p style="margin: 0 0 6px 0; font-size: 11px; font-weight: 700; color: #{t[:soft_text]}; text-transform: uppercase; letter-spacing: 1px;">
              #{esc(label)}
            </p>
            <div style="font-size: 36px; font-weight: 800; color: #{t[:accent]}; letter-spacing: 8px; font-family: 'Courier New', Courier, monospace; margin: 10px 0;">
              #{esc(code)}
            </div>
            #{expiry_html}
          </td>
        </tr>
      </table>
    HTML
  end

  def mailer_button(url:, text:, theme: :info)
    t = mailer_theme(theme)
    <<~HTML.html_safe
      <table role="presentation" width="100%" cellpadding="0" cellspacing="0" border="0" style="margin: 28px 0;">
        <tr>
          <td align="center">
            <table role="presentation" cellpadding="0" cellspacing="0" border="0">
              <tr>
                <td align="center" style="background-color: #{t[:accent]}; border-radius: 10px;">
                  <a href="#{esc(url)}" target="_blank" style="display: inline-block; padding: 14px 32px; font-size: 15px; font-weight: 700; color: #ffffff; text-decoration: none; border-radius: 10px; font-family: -apple-system, BlinkMacSystemFont, 'Segoe UI', Roboto, Helvetica, Arial, sans-serif;">
                    #{esc(text)}
                  </a>
                </td>
              </tr>
            </table>
          </td>
        </tr>
      </table>
    HTML
  end

  def mailer_notice(text, theme: :info, title: nil)
    t = mailer_theme(theme)
    title_html = title.present? ? %(<strong>#{esc(title)}</strong> ) : ""
    body = text.respond_to?(:html_safe?) && text.html_safe? ? text : esc(text)

    <<~HTML.html_safe
      <table role="presentation" width="100%" cellpadding="0" cellspacing="0" border="0" style="background-color: #{t[:soft_bg]}; border-left: 4px solid #{t[:accent]}; border-radius: 6px; margin: 20px 0;">
        <tr>
          <td style="padding: 14px 18px; font-size: 13px; color: #{t[:soft_text]}; line-height: 1.6;">
            #{title_html}#{body}
          </td>
        </tr>
      </table>
    HTML
  end

  def mailer_info_table(rows)
    rows_html = rows.map do |label, value|
      human_label = label.to_s.humanize
      resolved_value = value
      if label.to_s == "brand_id" || label.to_s.downcase == "brand"
        if value.is_a?(Integer) || (value.is_a?(String) && value =~ /^\d+$/)
          resolved_value = Brand.find_by(id: value)&.name || value
        end
        human_label = "Brand"
      elsif label.to_s == "category_id" || label.to_s.downcase == "category"
        if value.is_a?(Integer) || (value.is_a?(String) && value =~ /^\d+$/)
          resolved_value = Category.find_by(id: value)&.name || value
        end
        human_label = "Category"
      end

      %(<tr><td style="padding: 6px 0; color: #64748b; font-size: 13px; vertical-align: top; width: 35%; word-break: break-word; overflow-wrap: anywhere;">#{esc(human_label)}</td><td data-value="1" style="padding: 6px 0; color: #0f172a; font-size: 13px; font-weight: 600; text-align: right; vertical-align: top; word-break: break-word; overflow-wrap: anywhere; white-space: pre-line; line-height: 1.5;">#{esc(mailer_format_value(resolved_value))}</td></tr>)
    end.join

    <<~HTML.html_safe
      <table role="presentation" width="100%" cellpadding="0" cellspacing="0" border="0" style="background-color: #f8fafc; border: 1px solid #e2e8f0; border-radius: 12px; margin: 20px 0;">
        <tr>
          <td style="padding: 18px 20px;">
            <table role="presentation" width="100%" cellpadding="0" cellspacing="0" border="0" class="mailer-info-table" style="border-collapse: collapse; table-layout: fixed;">
              #{rows_html}
            </table>
          </td>
        </tr>
      </table>
    HTML
  end

  def mailer_changes_table(changes)
    rows_html = changes.map do |field, diff|
      from = diff[:from] || diff["from"]
      to   = diff[:to] || diff["to"]

      field_name = field.to_s.humanize
      if field.to_s == "brand_id" || field.to_s.downcase == "brand"
        field_name = "Brand"
        from = Brand.find_by(id: from)&.name || from if from.is_a?(Integer) || (from.is_a?(String) && from =~ /^\d+$/)
        to   = Brand.find_by(id: to)&.name || to if to.is_a?(Integer) || (to.is_a?(String) && to =~ /^\d+$/)
      elsif field.to_s == "category_id" || field.to_s.downcase == "category"
        field_name = "Category"
        from = Category.find_by(id: from)&.name || from if from.is_a?(Integer) || (from.is_a?(String) && from =~ /^\d+$/)
        to   = Category.find_by(id: to)&.name || to if to.is_a?(Integer) || (to.is_a?(String) && to =~ /^\d+$/)
      end

      %(<tr><td style="padding: 10px; font-weight: 600; color: #334155; border-bottom: 1px solid #f1f5f9; font-size: 13px; word-break: break-word; overflow-wrap: anywhere; vertical-align: top;">#{esc(field_name)}</td><td style="padding: 10px; color: #94a3b8; border-bottom: 1px solid #f1f5f9; font-size: 13px; word-break: break-word; overflow-wrap: anywhere; vertical-align: top; white-space: pre-line; line-height: 1.4;">#{esc(mailer_format_value(from))}</td><td style="padding: 10px; font-weight: 700; color: #059669; border-bottom: 1px solid #f1f5f9; font-size: 13px; word-break: break-word; overflow-wrap: anywhere; vertical-align: top; white-space: pre-line; line-height: 1.4;">#{esc(mailer_format_value(to))}</td></tr>)
    end.join

    <<~HTML.html_safe
      <table width="100%" cellpadding="0" cellspacing="0" class="mailer-changes-table" style="border-collapse: collapse; table-layout: fixed; font-size: 13px; border: 1px solid #e2e8f0; border-radius: 8px; margin: 16px 0;">
        <colgroup>
          <col style="width: 25%;"><col style="width: 37.5%;"><col style="width: 37.5%;">
        </colgroup>
        <thead>
          <tr style="background: #f1f5f9; color: #475569; text-align: left;">
            <th style="border-bottom: 1px solid #e2e8f0; padding: 10px; font-size: 12px;">Field</th>
            <th style="border-bottom: 1px solid #e2e8f0; padding: 10px; font-size: 12px;">Previous Value</th>
            <th style="border-bottom: 1px solid #e2e8f0; padding: 10px; font-size: 12px;">New Value</th>
          </tr>
        </thead>
        <tbody>
          #{rows_html}
        </tbody>
      </table>
    HTML
  end

  def mailer_detail_grid(details)
    mailer_info_table(details.map { |field, value| [field.to_s.humanize, value] })
  end

  def mailer_actor_block(name:, email: nil, theme: :info)
    t = mailer_theme(theme)
    initial = esc((name.presence || email.presence || "?").to_s[0].to_s.upcase)

    <<~HTML.html_safe
      <table role="presentation" cellpadding="0" cellspacing="0" border="0" style="background-color: #{t[:soft_bg]}; border: 1px solid #{t[:soft_border]}; border-radius: 8px; margin: 12px 0 20px 0;">
        <tr>
          <td style="padding: 12px 16px;">
            <table role="presentation" cellpadding="0" cellspacing="0" border="0">
              <tr>
                <td width="38" valign="middle" style="padding-right: 12px;">
                  <table role="presentation" cellpadding="0" cellspacing="0" border="0" style="width: 38px; height: 38px; background-color: #{t[:accent]}; border-radius: 50%;">
                    <tr><td align="center" valign="middle" style="color: #ffffff; font-weight: 700; font-size: 15px;">#{initial}</td></tr>
                  </table>
                </td>
                <td valign="middle">
                  <div style="font-weight: 700; font-size: 14px; color: #{t[:soft_text]};">#{esc(name.presence || "Administration")}</div>
                </td>
              </tr>
            </table>
          </td>
        </tr>
      </table>
    HTML
  end

  def mailer_order_item_row(name:, quantity:, price:)
    <<~HTML.html_safe
      <table role="presentation" width="100%" cellpadding="0" cellspacing="0" border="0" style="border: 1px solid #e5e7eb; border-radius: 8px; margin-bottom: 8px;">
        <tr>
          <td style="padding: 10px 14px;">
            <strong style="font-size: 14px; color: #0f172a;">#{esc(name)}</strong>
            <div style="font-size: 13px; color: #64748b; margin-top: 2px;">Qty: #{esc(quantity)}</div>
          </td>
          <td align="right" style="padding: 10px 14px; font-weight: 700; color: #0f766e; font-size: 14px; white-space: nowrap;">
            #{esc(price)}
          </td>
        </tr>
      </table>
    HTML
  end

  def mailer_order_totals(rows: [], total:)
    rows_html = rows.map do |label, value|
      %(<tr><td style="padding: 2px 0; color: #64748b; font-size: 13px;">#{esc(label)}</td><td align="right" style="padding: 2px 0; color: #334155; font-size: 13px;">#{esc(value)}</td></tr>)
    end.join

    <<~HTML.html_safe
      <table role="presentation" width="100%" cellpadding="0" cellspacing="0" border="0" style="border-top: 2px solid #e5e7eb; padding-top: 14px; margin-top: 16px;">
        #{rows_html}
        <tr><td style="padding: 6px 0 0; color: #0f172a; font-size: 18px; font-weight: 800;">Total</td><td align="right" style="padding: 6px 0 0; color: #0f766e; font-size: 18px; font-weight: 800;">#{esc(total)}</td></tr>
      </table>
    HTML
  end

  def format_currency(amount)
    "₹#{amount.to_f.round(2)}"
  end

  def format_amount(value)
    return "0.00" if value.blank?

    parts = sprintf("%.2f", value.to_f).split(".")
    integer_part = parts[0]
    decimal_part = parts[1]

    if integer_part.length > 3
      last_three = integer_part[-3..]
      other_digits = integer_part[0...-3]
      formatted_other = other_digits.reverse.gsub(/(\d{2})(?=\d)/, '\1,').reverse
      integer_part = "#{formatted_other},#{last_three}"
    end

    "#{integer_part}.#{decimal_part}"
  end

  def format_date(date)
    date.present? ? date.strftime("%d %B, %Y at %I:%M %p") : "N/A"
  end

  def payment_method_label(method)
    case method.to_s.downcase
    when "upi" then "UPI"
    when "card", "credit_card", "debit_card" then "Card"
    when "netbanking" then "Net Banking"
    when "cod" then "Cash on Delivery"
    when "online" then "Online Payment"
    else method.to_s.upcase
    end
  end

  def format_address(address)
    return "N/A" if address.blank?

    case address
    when Hash
      [
        address["address_line1"],
        address["address_line2"],
        address["city"],
        address["state"],
        address["postal_code"],
        address["country"]
      ].compact.reject(&:blank?).join(", ")
    when ActionController::Parameters
      format_address(address.to_unsafe_h)
    else
      address.to_s
    end
  end

  def payment_details(order)
    {
      method: payment_method_label(order.payment_method),
      status: order.payment_status.to_s.upcase,
      reference: order.payment_reference || order.gateway_order_reference || "N/A",
      paid_at: order.paid_at || order.payment_confirmed_at
    }
  end
end
