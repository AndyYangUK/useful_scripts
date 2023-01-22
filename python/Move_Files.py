import os
import pandas as pd
import time

# excel file name and sheet name variables
excel_file = "file.xlsx"
sheet_name = "Sheet1"

# error file name
error_file = "error_file.xlsx"

# read data from excel file
data = pd.read_excel(excel_file, sheet_name = sheet_name)

# variable to keep track of the number of files moved
filesMoved = 0

# start time of the script
startTime = time.time()

# loop through each row of data
for index, row in data.iterrows():
    # create the full path of the source file
    sourcePath = os.path.join(row["A"], row["B"])
    # create the full path of the destination file
    destinationPath = os.path.join(row["C"], row["D"])

    # check if the destination folder exists
    if not os.path.exists(destinationPath):
        # create the folder if it doesn't exist
        os.makedirs(destinationPath)

    # check if the source file exists
    if os.path.exists(sourcePath):
        # move the file from source to destination
        os.rename(sourcePath, destinationPath)
        # increment the number of files moved
        filesMoved += 1
    else:
        # write an error message in column E if the source file does not exist
        data.at[index, "E"] = "Source file not found"

# end time of the script
endTime = time.time()
# total time taken to move the files
totalTime = endTime - startTime

# write the updated data to the excel file

# write only the rows that have an error message
data[data["E"] == "Source file not found"].to_excel(error_file, index=False)

# print the number of files moved and the total time taken
print(f'{filesMoved} files were moved in {totalTime} seconds.')
