package main

import (
	"bufio"
	"fmt"
	"os"
	"strings"
	"time"

	"github.com/alecthomas/kong"
	"github.com/google/uuid"
)

type CLI struct {
    Filter FilterCmd `kong:"cmd,help='Filters the database dumps based on provided criteria.'"`
}

type FilterCmd struct {
    Filename        string `kong:"arg,required,help='Path to the Testing Farm sql dump to process. Use \"stdin\" to read from standard input.'"`
    Date            string `kong:"arg,required,help='Filter only requests newer then the given date.'"`
    ValuesBatchSize int    `kong:"optional,type='int',help='Batch size of the added values.',default=100"`
    RequestsFile    string `kong:"optional,type='path',help='Optional file containing additional requests to include.'"`
}

func main() {
    cli := CLI{}

    ctx := kong.Parse(&cli, kong.Description("dbtool: Testing Farm database manipulation tool."),
        kong.UsageOnError(),
        kong.ConfigureHelp(kong.HelpOptions{
            Compact: false,
            Summary: true,
        }))

	err := ctx.Run()  // Directly call ctx.Run() to handle the command execution
	ctx.FatalIfErrorf(err)
}

func (fc *FilterCmd) Run() error {
	dateThreshold, err := time.Parse("2006-01-02", fc.Date)
	if err != nil {
		return fmt.Errorf("Error parsing date: %v", err)
	}

	var file *os.File
	var requests[] string;

	// read requests file
	if fc.RequestsFile != "" {
        file, err := os.Open(fc.RequestsFile)
        if err != nil {
            return fmt.Errorf("failed to open requests file: %v", err)
        }
        defer file.Close()

        scanner := bufio.NewScanner(file)

        for scanner.Scan() {
			_, err := uuid.Parse(scanner.Text())
			if err != nil {
				return fmt.Errorf("Request '%v' is not a valid UUID4", scanner.Text())
			}
			requests = append(requests, scanner.Text())
        }

        if err := scanner.Err(); err != nil {
            return fmt.Errorf("failed to read from requests file: %v", err)
        }
    }

	// set reading from stdin or from the given file
	if fc.Filename == "stdin" {
		file = os.Stdin
	} else {
		file, err = os.Open(fc.Filename)
		if err != nil {
			return fmt.Errorf("Error opening file: %v", err)
		}
		defer file.Close()
	}

	// lines are very long, use 100MB buffer
	const maxCapacity = 100 * 1024 * 1024

	scanner := bufio.NewScanner(file)
	buf := make([]byte, 0, maxCapacity)
	scanner.Buffer(buf, maxCapacity)

	max_values := fc.ValuesBatchSize

	var insert string
	var value string
	var printed_values = 0
	var insert_printed = false
	var print_newline = false
	var is_insert = false

	// flush an insert value
	flush_value := func() {
		if value != "" {
			fmt.Println(value)
			value = ""
			printed_values++
		}
	}

	// flush an last insert value
	flush_last_value := func() {
		if value != "" {
			if printed_values < max_values {
				value = value[0:len(value)-1] + ";"
				flush_value()
			} else {
				flush_value()
			}
		}
	}

	for scanner.Scan() {
		line := scanner.Text()

		// remember that an INSERT INTO sql command has started
		if strings.HasPrefix(line, "INSERT INTO requests") {
			insert = line
			print_newline = false
			is_insert = true

		} else if is_insert && strings.HasPrefix(line, "\t('") {
			// handle values for INSERT INTO
			if containsDateAfter(line, dateThreshold) || containsRequests(line, requests) {

				// flush insert value
				flush_value()

				if printed_values >= max_values {
					printed_values = 0
				}

				// print INSERT INTO statement if the values counter is 0 or insert not printed
				if printed_values == 0 || !insert_printed {
					if print_newline {
						fmt.Println()
						print_newline = false
					}
					fmt.Println()
					fmt.Println(insert)
					insert_printed = true
				}

				// next value to print, in case it is the last, make sure
				// it ends the statement
				if printed_values == max_values-1 {
					value = line[0:len(line)-1] + ";"
				} else {
					value = line[0:len(line)-1] + ","
				}
			}

		} else if line == "" && !print_newline {
			// handle empty lines
			print_newline = true
		} else {
			// handle other statements
			flush_last_value()
			if print_newline {
				fmt.Println()
				print_newline = false
			}
			fmt.Println(line)
			insert_printed = false
			is_insert = false
		}
	}

	// flush last value
	flush_last_value()

	if err := scanner.Err(); err != nil {
		fmt.Println("Error reading file:", err)
	}

	return nil;
}

func containsDateAfter(data string, dateThreshold time.Time) bool {
	start := strings.Index(data, "('")
	if start == -1 {
		// failed to parse
		return false
	}
	start += 2
	end := strings.Index(data[start:], " ")
	if end == -1 {
		// failed to parse
		return false
	}
	dateStr := data[start : start+end]
	date, err := time.Parse("2006-01-02", dateStr)
	if err != nil {
		// failed to parse
		return false
	}
	return date.After(dateThreshold)
}

func containsRequests(data string, requests[] string) bool {
	for _, request := range requests {
		if strings.Index(data[:200], request) != -1 {
			return true
		}
	}

	return false
}
