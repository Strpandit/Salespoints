module RejectReasonValidator
  MIN_LENGTH = 5
  MAX_LENGTH = 200
  ALLOWED_CHARACTERS = /\A[A-Za-z0-9 .,;:'"()\/&%#!?+\-]+\z/
  PUNCTUATION_FIXES = { "‘" => "'", "’" => "'", "“" => '"', "”" => '"', "–" => "-", "—" => "-" }.freeze

  module_function

  def validate(raw)
    text = normalize(raw)

    return [nil, "Please enter a reason for rejecting this order."] if text.blank?
    return [nil, "Please enter at least #{MIN_LENGTH} characters so that the reason is clear."] if text.length < MIN_LENGTH
    return [nil, "The reason must not exceed #{MAX_LENGTH} characters."] if text.length > MAX_LENGTH
    return [nil, "Please write the reason in English, using letters, numbers and standard punctuation only."] unless text.match?(ALLOWED_CHARACTERS)

    words = text.split(" ").count { |word| word.match?(/[A-Za-z]/) }
    letters = text.count("A-Za-z")
    return [nil, "Please enter a meaningful reason of at least two words, for example: \"Product is out of stock\"."] if words < 2 || letters < 4
    return [nil, "Please enter a genuine reason without repeated characters."] if text.match?(/(.)\1{4,}/)

    [text, nil]
  end

  def normalize(raw)
    text = raw.to_s.dup
    PUNCTUATION_FIXES.each { |from, to| text.gsub!(from, to) }
    text = text.squish
    text[0] = text[0].upcase if text.present?
    text
  end
end
