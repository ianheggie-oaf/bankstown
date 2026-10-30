#!/usr/bin/env ruby
# frozen_string_literal: true

# Scrapes development applications for Canterbury-Bankstown Council.
#
# The council's DA tracker lists every application lodged in a period (this
# week, this month, last month and so on) on a single page with no paging.
# Each application is an article card holding the reference, a
# "Type - description" paragraph and dt/dd pairs for Address and Lodged.
# It covers DAs, complying development and construction certificates,
# including those from private certifiers.
#
# DAs on exhibition are only published on the NSW Planning Portal, under PAN
# references, so they are not scraped here.
#
# See https://github.com/planningalerts-scrapers/issues/issues/1459

require "bundler/setup"
Bundler.require

require "scraperwiki"
require "mechanize"
require "date"

class Scraper
  BASE_URL = "https://eplanning.cbcity.nsw.gov.au"
  LIST_URL = "#{BASE_URL}/ApplicationSearch/SearchByLodgementDate?mode=view-applications-lodged&filter=".freeze

  # Last month as well as this month, so there are always at least 30 days of
  # applications early in the month
  DEFAULT_PERIODS = %w[thismonth lastmonth].freeze
  PERIODS = %w[yesterday thisweek lastweek thismonth lastmonth].freeze

  # An application missing something PlanningAlerts needs is skipped with a
  # warning, but the run stops once there are more than 10 + 20% of good ones
  class BadApplication < StandardError; end

  def self.run
    new.run
  end

  def initialize
    @agent = Mechanize.new
    if ENV["MORPH_AUSTRALIAN_PROXY"]
      # On morph.io set the environment variable MORPH_AUSTRALIAN_PROXY to
      # http://morph:password@au.proxy.oaf.org.au:8888 replacing password with
      # the real password.
      puts "Using Australian proxy..."
      @agent.agent.set_proxy(ENV["MORPH_AUSTRALIAN_PROXY"])
    end
    @debug = !ENV["MORPH_DEBUG"].to_s.empty?
    @saved = 0
    @skipped = 0
  end

  def run
    puts "Running ruby #{RUBY_VERSION}"
    periods.each_with_index do |period, index|
      sleep 1 if index.positive?
      scrape_period(period)
    end
    # Doesn't check which records are new, so reports them all as saved
    puts "", "Finished - saved #{@saved} records#{", skipped #{@skipped} bad applications" if @skipped.positive?}"
  end

  private

  # MORPH_PERIOD picks a single period, for example lastweek, for data recovery
  def periods
    period = ENV["MORPH_PERIOD"].to_s
    return DEFAULT_PERIODS if period.empty?
    return [period] if PERIODS.include?(period)

    raise "Unknown MORPH_PERIOD #{period.inspect}, expected one of #{PERIODS.join(', ')}"
  end

  def scrape_period(period)
    url = LIST_URL + period
    puts "", "Scraping applications lodged #{period}..."
    page = @agent.get(url)
    summary = page.at("#application-search-results .results-summary-title")
    raise "No results summary found at #{url}" unless summary

    expected = clean_text(summary.text)[/\A(\d+) applications? found/, 1]
    raise "Unexpected results summary #{clean_text(summary.text).inspect} at #{url}" unless expected

    cards = page.search("article.application-result-card")
    raise "Expected #{expected} applications but found #{cards.size} at #{url}" unless cards.size == expected.to_i

    cards.each_with_index { |card, index| save_card(card, "#{period} card #{index + 1}") }
    puts "Finished #{period} - processed #{cards.size} records"
  end

  def save_card(card, position)
    save(parse_card(card))
  rescue BadApplication => e
    @skipped += 1
    puts "Skipping bad application (#{position}): #{e.message}"
    return if @skipped <= 10 + (@saved / 5.0)

    raise "Too many bad applications: skipped #{@skipped}, saved #{@saved}"
  end

  # Raises BadApplication when the reference, details link or address is
  # missing, or the lodged date can't be read
  def parse_card(card)
    link = card.at("a.application-details-link")
    reference = clean_text(link&.text)
    raise BadApplication, "no application number" if reference.empty?
    raise BadApplication, "#{reference} has no details link" if link["href"].to_s.empty?

    fields = card_fields(card)
    address = fields["Address"].to_s
    raise BadApplication, "#{reference} has no address" if address.empty?

    {
      "council_reference" => reference,
      "address" => address,
      "description" => description(card),
      "info_url" => URI.join(BASE_URL, link["href"]).to_s,
      "date_scraped" => Date.today.to_s,
      "date_received" => parse_lodged(reference, fields["Lodged"]),
    }
  end

  def parse_lodged(reference, lodged)
    Date.strptime(lodged.to_s, "%d/%m/%Y").to_s
  rescue Date::Error
    raise BadApplication, "#{reference} has an unreadable lodged date #{lodged.inspect}"
  end

  # Maps each dt label to its dd value, keeping the first of any repeated label
  def card_fields(card)
    card.search("dt").each_with_object({}) do |dt, fields|
      fields[clean_text(dt.text)] ||= clean_text(dt.next_element&.text)
    end
  end

  # The description starts with the application type, for example
  # "Development Application - Construction of a dual occupancy"
  def description(card)
    text = clean_text(card.at("p.application-result-description")&.text)
    _type, description = text.split(" - ", 2)
    description.to_s.empty? ? text : description
  end

  # Collapses whitespace, including the non-breaking spaces used in addresses
  def clean_text(text)
    text.to_s.gsub(/[[:space:]]+/, " ").strip
  end

  def save(record)
    puts "Storing #{record['council_reference']} - #{record['address']}"
    puts "RECORD: #{record.inspect}" if @debug
    ScraperWiki.save_sqlite(["council_reference"], record)
    @saved += 1
  end
end

Scraper.run if __FILE__ == $PROGRAM_NAME
