# Normalises a free-text search box value into AND-ed tokens.
#
# Search suggestions are labelled like "LG 10.5 kg Washing Machine [SKU: P105ASRAZ]" or
# "Vivo Y-30 (4-64)"; picking one pastes the whole label back into the search box. Matching that
# literally never hits anything, so the marker words ("SKU:", "HSN:", "Model:") and the
# brackets are dropped and the code itself becomes one more token, matched against SKU / HSN
# columns just like every other word is matched against name columns.
module SearchQuery
  MARKER = /\[\s*(?:sku|hsn|hsn code|model|model no|model number)\s*:\s*([^\]]+)\]/i

  def self.tokens(raw)
    text = raw.to_s.strip.gsub(MARKER) { " #{Regexp.last_match(1)} " }
    clean = text.downcase.gsub(/[^a-z0-9\.\-\/]/, " ")
    tokens = clean.split(/\s+/).map { |t| t.gsub(/\A[\.\-\/]+|[\.\-\/]+\z/, "") }.reject { |t| t.blank? || t.length < 2 }
    tokens = [raw.to_s.strip.downcase] if tokens.empty? && raw.to_s.strip.present?
    tokens.uniq
  end

  # scope.where(...) per token; every token must match at least one of `predicates`
  # (SQL snippets using the :p placeholder, e.g. "products.name ILIKE :p").
  def self.apply(scope, raw, predicates)
    tokens(raw).each do |t|
      scope = scope.where(predicates.join(" OR "), p: "%#{ActiveRecord::Base.sanitize_sql_like(t)}%")
    end
    scope
  end
end
