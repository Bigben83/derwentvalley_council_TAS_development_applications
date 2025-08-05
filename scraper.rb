require 'capybara'
require 'selenium-webdriver'
require 'nokogiri'
require 'sqlite3'
require 'logger'
require 'date'

logger = Logger.new(STDOUT)

Capybara.register_driver :selenium_chrome_headless_morph do |app|
  Capybara::Selenium::Driver.load_selenium
  options = ::Selenium::WebDriver::Chrome::Options.new
  options.add_argument('--headless')
  options.add_argument('--disable-gpu')
  options.add_argument('--no-sandbox')
  options.add_argument('--disable-site-isolation-trials')
  Capybara::Selenium::Driver.new(app, browser: :chrome, options: options)
end

session = Capybara::Session.new(:selenium_chrome_headless_morph)

# Visit the page with browser emulation
logger.info("Visiting page: https://www.derwentvalley.tas.gov.au/home/latest-news?f.News+category%7CnewsCategory=Public+Notice")
session.visit('https://www.derwentvalley.tas.gov.au/home/latest-news?f.News+category%7CnewsCategory=Public+Notice')

# Wait for page content to load
sleep 5 # (or better yet, implement Capybara's wait for elements)

# Parse with Nokogiri
doc = Nokogiri::HTML(session.html)

# Now process .news-listing__item as before...
logger.info("Found #{doc.css('.news-listing__item').count} news items.")


# Step 3: Initialize the SQLite database
db = SQLite3::Database.new "data.sqlite"

# Create table
db.execute <<-SQL
  CREATE TABLE IF NOT EXISTS derwentvalley (
    id INTEGER PRIMARY KEY,
    description TEXT,
    date_scraped TEXT,
    date_received TEXT,
    on_notice_to TEXT,
    address TEXT,
    council_reference TEXT,
    applicant TEXT,
    owner TEXT,
    stage_description TEXT,
    stage_status TEXT,
    document_description TEXT,
    title_reference TEXT
  );
SQL

# Define variables for storing extracted data for each entry
address = ''  
description = ''
on_notice_to = ''
title_reference = ''
date_received = ''
council_reference = ''
applicant = ''
owner = ''
stage_description = ''
stage_status = ''
document_description = ''
date_scraped = Date.today.to_s

# Loop through each item in the main listing
main_page.css('.news-listing__item').each do |item|
  title = item.at_css('.news-listing__item-title').text.strip
  date = item.at_css('.news-listing__item-date').text.strip

  # Extract the council reference, address, and description from the title
  council_reference = title.match(/DA \d+/)&.to_s
  address = title.match(/- (.*?) -/)&.captures&.first
  description = title.match(/- (.*?)$/)&.captures&.first

  # Parse the date (adjust format if needed)
  date = Date.strptime(date, "%d %B %Y").to_s # Adjust this format if necessary

  # Log the extracted data from the main page
  logger.info("Council Reference: #{council_reference}, Address: #{address}, Description: #{description}, Date: #{date}")

  # Extract the link to the detailed page
  detail_link = item.at_css('.news-listing__item-link')['href']
  
  # Open and parse the detailed page
  begin
    detailed_html = open(detail_link, "User-Agent" => "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/115.0.0.0 Safari/537.36").read
    detailed_page = Nokogiri::HTML(detailed_html)
  rescue => e
    logger.error("Failed to fetch detailed page #{detail_link}: #{e}")
    next
  end

  # Extracting the table data for council reference, address, and description
  council_reference_detail = detailed_page.at_css('table tbody tr td:nth-child(1)').text.strip
  address_detail = detailed_page.at_css('table tbody tr td:nth-child(2)').text.strip
  description_detail = detailed_page.at_css('table tbody tr td:nth-child(3)').text.strip

  # Extracting the "Start Date" (on_notice_from)
  on_notice_from = detailed_page.at_css('p:contains("Start Date")').text.strip
  on_notice_from_date = on_notice_from.match(/Start Date (\d{2}\/\d{2}\/\d{2})/)&.captures&.first
  on_notice_from_date = Date.strptime(on_notice_from_date, "%d/%m/%y").to_s if on_notice_from_date

  # Extracting "on_notice_to" date
  on_notice_to = detailed_page.at_css('p:contains("received no later than")').text.strip
  on_notice_to_date = on_notice_to.match(/received no later than (\d{2} \w+ \d{4})/)&.captures&.first
  on_notice_to_date = Date.strptime(on_notice_to_date, "%d %B %Y").to_s if on_notice_to_date

  # Log the extracted data from the detailed page
  logger.info("Council Reference: #{council_reference_detail}, Address: #{address_detail}, Description: #{description_detail}, On Notice From: #{on_notice_from_date}, On Notice To: #{on_notice_to_date}")
  
  
end
session.quit
