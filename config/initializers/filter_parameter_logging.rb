Rails.application.config.filter_parameters += [
  :passw, :email, :secret, :token, :_key, :crypt, :salt, :certificate, :otp, :ssn, :cvv, :cvc,
  :card, :pan, :account_number, :ifsc, :aadhar, :bank_account_number, :routing_number
]
