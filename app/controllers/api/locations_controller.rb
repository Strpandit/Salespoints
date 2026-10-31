module Api
  class LocationsController < Api::ApplicationController
    LAT_RANGE = (6.0..38.0).freeze
    LNG_RANGE = (68.0..98.0).freeze

    def reverse_geocode
      lat = Float(params[:lat].to_s, exception: false)
      lng = Float(params[:lng].to_s, exception: false)
      unless lat && lng && LAT_RANGE.cover?(lat) && LNG_RANGE.cover?(lng)
        return render json: { error: "A valid latitude and longitude in India are required" }, status: :unprocessable_entity
      end

      address = GoogleMapsService.instance.reverse_geocode_for_address(lat, lng)
      return render json: { error: "Address not found for this location" }, status: :not_found if address.blank?

      render json: { data: address }, status: :ok
    end
  end
end
