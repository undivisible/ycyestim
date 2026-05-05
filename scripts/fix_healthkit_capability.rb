project_file = File.join(__dir__, "..", "YCYEStim.xcodeproj", "project.pbxproj")
contents = File.read(project_file)

malformed = 'SystemCapabilities = "[\"com.apple.HealthKit\": [\"enabled\": 1]]";'
healthkit_capability = <<~PBX.strip
SystemCapabilities = {
\t\t\t\t\t\tcom.apple.HealthKit = {
\t\t\t\t\t\t\tenabled = 1;
\t\t\t\t\t\t};
\t\t\t\t\t};
PBX

updated = contents.gsub(malformed, healthkit_capability)
File.write(project_file, updated)
puts "Xcode project generated successfully"
