package main

import "core:strconv"
import "core:os"
import "core:strings"
import "core:time"
import "core:slice"
import pqueue "core:container/priority_queue"
import "core:fmt"

Stack :: struct {
   count: int,
   item_id: int,
}

Recipe :: struct {
   input: []Stack,
   output: []Stack,
   recipe_time: time.Duration,
}

recipes: map[string]Recipe

Token_Type :: enum {
   Ident, 
   Number, 
   Plus, 
   Arrow, 
   Vert_Line, 
   Colon,
   Comma,
   EOF,
}

Token_Pos :: struct {
   line: u32,
   column: u32,
}

Token :: struct {
   type: Token_Type,
   str: string,
   pos: Token_Pos,
}

Tokenizer :: struct {
   str: string,
   pos: Token_Pos,
}

pop_chars_no_newline :: proc(line: ^Tokenizer, count: int) -> string {
   res := line.str[:count]
   line.str = line.str[count:]
   line.pos.column += u32(count)
   return res
}

Token_Result :: enum {
   Ok,
   None,
   Error,
}

// This function returns and prints an error if there is unparsable token.
// For EOF a token with type .EOF is returned
get_next_token :: proc(t: ^Tokenizer) -> (part: Token, ok: bool) {
   t.str = strings.trim_left_space(t.str)

   for {
      pos := t.pos
      if len(t.str) == 0 {
         return {.EOF, "End of file", pos}, true
      }
      switch t.str[0] {
         case '+':
            return {.Plus, pop_chars_no_newline(t, 1), pos}, true
         case ':':
            return {.Colon, pop_chars_no_newline(t, 1), pos}, true
         case ',':
            return {.Comma, pop_chars_no_newline(t, 1), pos}, true
         case '-':
            if len(t.str) >= 2 && t.str[1] == '>' {
               return {.Arrow, pop_chars_no_newline(t, 2), pos}, true
            }
            else {
               errorf_pos(pos, "Unknown token")
               return {}, false
            }
         case '|':
            return {.Vert_Line, pop_chars_no_newline(t, 1), pos}, true
         case '\n':
            t.str = t.str[1:]
            t.pos.column = 0
            t.pos.line += 1
         case ' ', '\t', '\v':
            pop_chars_no_newline(t, 1)
         case '0'..='9':
            for i in 1..<len(t.str) {
               if !('0' <= t.str[i] && t.str[i] <= '9') {
                  return {.Number, pop_chars_no_newline(t, i), pos}, true
               }
            }
            return {.Number, pop_chars_no_newline(t, len(t.str)), pos}, true
         case 'a'..='z', 'A'..='Z', '_', '$', '#', '%':
            for i in 1..<len(t.str) {
               switch t.str[i] {
                  case 'a'..='z', 'A'..='Z', '_', '$', '#', '%', '0'..='9':
                     continue
                  case:
                     return {.Ident, pop_chars_no_newline(t, i), pos}, true
               }
            }
            return {.Ident, pop_chars_no_newline(t, len(t.str)), pos}, true
         case:
            errorf_pos(pos, "Unknown token, char: {}", int(t.str[0]))
            return {}, false
      }
   }
}


get_token_expect_type :: proc(tokenizer: ^Tokenizer, type: Token_Type) -> (res: Token, ok: bool) {
   token := get_next_token(tokenizer) or_return
   if token.type == type {
      return token, true
   }
   expect_message(token.pos, type, token.type)
   return token, false
}

expect_token :: proc(tokenizer: ^Tokenizer, type: Token_Type) -> (ok: bool) {
   _, ok = get_token_expect_type(tokenizer, type)
   return ok
}

try_parse_stack :: proc(t: ^Tokenizer, item_name_mapping: ^map[string]int) -> (res: Stack, attempt_success: bool, ok: bool) {
   t_save := t^
   tok := get_next_token(t) or_return
   if tok.type == .Ident {
      if tok.str not_in item_name_mapping {
         item_name_mapping[tok.str] = len(item_name_mapping)
      }
      return Stack{count = 1, item_id = item_name_mapping[tok.str]}, true, true
   }
   else if tok.type == .Number {
      count, _ := strconv.parse_int(tok.str)
      name := get_next_token(t) or_return
      if name.type != .Ident {
         expect_message(name.pos, .Ident, name.type)
         t^ = t_save
         return {}, false, false
      }
      if name.str not_in item_name_mapping {
         item_name_mapping[name.str] = len(item_name_mapping)
      }
      item_id := item_name_mapping[name.str]
      return Stack{count = count, item_id = item_id}, true, true
   }
   else {
      t^ = t_save
      return {}, false, true
   }
}

parse_stack_sum :: proc(t: ^Tokenizer, item_name_mapping: ^map[string]int) -> (res: []Stack, ok: bool) {
   stacks: [dynamic]Stack
   defer delete(stacks)

   for {
      stack, stack_success := try_parse_stack(t, item_name_mapping) or_return
      if !stack_success {
         break
      }
      append(&stacks, stack)
      t_save_state := t^
      plus_ig := get_next_token(&t_save_state) or_return
      if plus_ig.type != .Plus {
         break
      }
      else {
         t^ = t_save_state
      }
   }

   res = slice.clone(stacks[:])
   return res, true
}

parse_recipe :: proc(tokenizer: ^Tokenizer, item_name_mapping: ^map[string]int) -> (recipe_name: string, recipe: Recipe, ok: bool) {
   recipe_name_token := get_next_token(tokenizer) or_return

   if recipe_name_token.type != .Ident {
      errorf_line(recipe_name_token.pos.line, "Name of the recipe must be an identifier, got {}", recipe_name_token.type)
      return {}, {}, false
   }

   expect_token(tokenizer, .Colon) or_return

   // r_fecl3: fe + 3 hcl => fecl3, 30s

   input_stacks := parse_stack_sum(tokenizer, item_name_mapping) or_return
   expect_token(tokenizer, .Arrow) or_return
   output_stacks := parse_stack_sum(tokenizer, item_name_mapping) or_return
   expect_token(tokenizer, .Comma) or_return
   time_val: time.Duration = 0
   for {
      time_number := get_next_token(tokenizer) or_return
      time_spec := get_next_token(tokenizer) or_return
      if time_number.type == .EOF {
         break
      }
      if !(time_number.type == .Number && time_spec.type == .Ident) {
         errorf_pos(time_number.pos, "Wrong time specifier")
      }
      count, _ := strconv.parse_int(time_number.str)
      mult: time.Duration
      switch time_spec.str {
         case "t", "tick":
            mult = time.Second / 20
         case "s", "sec":
            mult = time.Second
         case "m", "min":
            mult = time.Minute
         case "h", "hour":
            mult = time.Hour
         case "d", "day":
            mult = time.Hour * 24
      }
      time_val += time.Duration(count) * mult
   }
   expect_token(tokenizer, .EOF) or_return

   recipe = Recipe{
      input = input_stacks,
      output = output_stacks,
      recipe_time = time_val,
   }

   return recipe_name_token.str, recipe, true
}

recipe_to_string :: proc(recipe: Recipe, count: int, item_name_unmapping: [dynamic]string) -> string {
   sb: strings.Builder
   defer strings.builder_destroy(&sb)

   fmt.sbprint(&sb, "{")
   fmt.sbprint(&sb, "Input: ")
   for stack, index in recipe.input {
      if index != 0 {
         fmt.sbprintf(&sb, ", ")
      }
      fmt.sbprintf(&sb, "{}x {}", stack.count * count, item_name_unmapping[stack.item_id])
   }
   fmt.sbprint(&sb, ", Output: ")
   for stack, index in recipe.output {
      if index != 0 {
         fmt.sbprintf(&sb, ", ")
      }
      fmt.sbprintf(&sb, "{}x {}", stack.count * count, item_name_unmapping[stack.item_id])
   }

   fmt.sbprintf(&sb, ", Time: {}", recipe.recipe_time * time.Duration(count))
   fmt.sbprint(&sb, "}")
   return strings.clone(strings.to_string(sb))
}

_main :: proc() -> bool {
   if len(os.args) != 2 {
      fmt.printfln("Usage: {} <file name>", os.args[0])
      return false
   }
   file_name := os.args[1]
   recipe_file_contents, recipe_file_contents_ok := os.read_entire_file_from_filename(file_name)
   if !recipe_file_contents_ok {
      errorf_none("File doesn't exist: {}", file_name)
      return false
   }

   lines := strings.split_lines(cast(string)recipe_file_contents)

   Mode :: enum {
      None,
      Recipes,
      Machines,
      Input,
      Output,
      Local,
      Process,
   }

   mode: Mode
   seen: [Mode]int
   end: [Mode]int
   for &v in seen {
      v = -1
   }
   for &v in end {
      v = len(lines)
   }
   error: bool
   for line, line_index in lines {
      line := strings.trim_space(line)
      line_number := line_index + 1
      new_mode_opt: Maybe(Mode)
      switch line {
         case "RECIPES":
            new_mode_opt = .Recipes
         case "MACHINES":
            new_mode_opt = .Machines
         case "INPUT":
            new_mode_opt = .Input
         case "OUTPUT":
            new_mode_opt = .Output
         case "LOCAL":
            new_mode_opt = .Local
         case "PROCESS":
            new_mode_opt = .Process
      }

      if new_mode, new_mode_ok := new_mode_opt.(Mode); new_mode_ok {
         if seen[new_mode] != -1 {
            errorf_line(auto_cast line_number, "Section repeated, previous occurence {}", seen[new_mode] + 1)
            error = true
         }
         seen[new_mode] = line_index
         end[mode] = line_index
         mode = new_mode
      }
   }

   for v, m in seen {
      if m != .None && v == -1 {
         errorf_none("Section missing: {}", m)
         error = true
      }
   }

   if error {
      return false
   }

   line_intervals: [Mode][]string
   for m in Mode {
      line_intervals[m] = lines[seen[m] + 1:end[m]]
   }

   machine_name_to_id: map[string]int
   defer delete(machine_name_to_id)

   machine_id_to_name: [dynamic]string
   defer delete(machine_id_to_name)
   // Parse Machines
   machine_loop: for line, index in line_intervals[.Machines] {
      t := Tokenizer{
         str = line,
         pos = {line = u32(index + seen[.Machines] + 2), column = 0},
      }
      name := get_next_token(&t) or_return

      if name.type == .EOF {
         continue
      }

      {
         next_tok := get_next_token(&t) or_return

         if next_tok.type != Token_Type.EOF {
            errorf_line(t.pos.line, "There can only be one machine per line: {}", line)
            continue
         }
      }

      if name.type != .Ident {
         errorf_line(t.pos.line, "Machine name has to be an identifier, got {} which is of type {}", name.str, name.type)
         error = true
         continue
      }

      if name.str in machine_name_to_id {
         errorf_line(t.pos.line, "Error: line {}, machine name repeated: {}", name.str)
         error = true
         continue
      }
      machine_name_to_id[name.str] = len(machine_name_to_id)
      append(&machine_id_to_name, name.str)
   }

   item_name_mapping: map[string]int
   defer delete(item_name_mapping)

   input: [dynamic]Stack
   defer delete(input)

   output: [dynamic]Stack
   defer delete(output)

   local: [dynamic]Stack
   defer delete(local)

   parse_items :: proc(interval: []string, input: ^[dynamic]Stack, error: ^bool, item_name_mapping: ^map[string]int, seen_index: int) {
      for line, index in interval {
         t := Tokenizer{
            str = line,
            pos = {line = u32(index + seen_index + 1), column = 0},
         }
         // We ignore errors
         result_stack, success, no_error_stack := try_parse_stack(&t, item_name_mapping)
         if !no_error_stack {
            error^ = true
            continue
         }
         next, no_error_eof := get_next_token(&t)
         if !no_error_eof {
            error^ = true
         }
         if next.type != .EOF {
            errorf_pos(next.pos, "Expected end of line")
            error^ = true
         }
         if success {
            append_elem(input, result_stack)
         }
      }
   }

   // Parse Inputs
   parse_items(line_intervals[.Input], &input, &error, &item_name_mapping, seen[.Input])

   // Parse Outputs
   parse_items(line_intervals[.Output], &output, &error, &item_name_mapping, seen[.Output])

   // Parse Local
   parse_items(line_intervals[.Local], &local, &error, &item_name_mapping, seen[.Local])

   // Parse Recipes
   for line, index in line_intervals[.Recipes] {
      t := Tokenizer{
         str = line,
         pos = {line = u32(index + seen[.Recipes] + 2), column = 0},
      }
      if strings.trim_left_space(line) == "" {
         continue
      }
      recipe_name, recipe, recipe_ok := parse_recipe(&t, &item_name_mapping)
      if !recipe_ok {
         error = true
         continue
      }
      if recipe_name in recipes {
         errorf_line(t.pos.line, "Repeated recipe name \"{}\"", recipe_name)
         error = true
      }
      recipes[recipe_name] = recipe
   }

   if error {
      return false
   }

   inventory := make([]int, len(item_name_mapping))
   for stack in input {
      inventory[stack.item_id] += stack.count
   }

   for stack in local {
      inventory[stack.item_id] += stack.count
   }


   current_recipe := make_slice([]Maybe(^Recipe), len(machine_name_to_id))
   defer delete(current_recipe)

   current_recipe_count := make_slice([]int, len(machine_name_to_id))
   defer delete(current_recipe_count)

   current_time := time.Duration(0)

   PQ_Key :: struct {
      time: time.Duration,
      machine_id: int,
   }

   pq_key_less :: proc(a, b: PQ_Key) -> bool {
      if a.time != b.time {
         return a.time < b.time
      }
      return a.machine_id < b.machine_id
   }

   next_action_queue: pqueue.Priority_Queue(PQ_Key)
   pqueue.init(&next_action_queue, pq_key_less, pqueue.default_swap_proc(PQ_Key))
   defer pqueue.destroy(&next_action_queue)

   defined_tags: map[string]time.Duration

   item_name_unmapping := make([dynamic]string, len(item_name_mapping))
   defer delete(item_name_unmapping)

   for name, id in item_name_mapping {
      item_name_unmapping[id] = name
   }

   for line, index in line_intervals[.Process] {
      t := Tokenizer{
         str = line,
         pos = {line = u32(index + seen[.Process] + 2), column = 0},
      }

      used_tags: [dynamic]string
      defer delete(used_tags)

      is_valid := true
      // [3] r_hcl,cr1|hcl -> hcl
      recipe_count := get_next_token(&t) or_return
      if recipe_count.type == .EOF {
         continue
      }
      // 3 [r_hcl],cr1|hcl -> hcl
      recipe_name := get_next_token(&t) or_return

      // 3 r_hcl[,]cr1|hcl -> hcl
      expect_token(&t, .Comma) or_return
      // 3 r_hcl,[cr1]|hcl -> hcl
      machine_name := get_next_token(&t) or_return

      // 3 r_hcl,cr1[|hcl] -> hcl
      for {
         t_save := t
         line := get_next_token(&t) or_return
         if line.type != .Vert_Line {
            t = t_save
            break
         }
         tag := get_token_expect_type(&t, .Ident) or_return
         append(&used_tags, tag.str)
      }

      // 3 r_hcl,cr1|hcl [->] hcl
      //1 r_fecl3,cr2|hcl [EOF]
      tag: Maybe(string)
      arrow_or_nothing := get_next_token(&t) or_return
      if arrow_or_nothing.type == .EOF {
      }
      else if arrow_or_nothing.type == .Arrow {
         tag_name_tok := get_next_token(&t) or_return
         if tag_name_tok.type != .Ident {
            is_valid = false
         }
         tag = tag_name_tok.str
         eof_token := get_next_token(&t) or_return
         if eof_token.type != .EOF {
            is_valid = false
         }
      }

      is_valid = is_valid && recipe_name.type == .Ident && machine_name.type == .Ident && 
         recipe_count.type == .Number

      if !is_valid {
         errorf_line(t.pos.line, "Expected format: <recipe count> <recipe_name>,<machine_name>[|tag][|tag]...[-> tag], got {}", line)
         return false
      }
      
      count, _ := strconv.parse_int(recipe_count.str)
      recipe, recipe_ok := &recipes[recipe_name.str]
      machine, machine_ok := machine_name_to_id[machine_name.str]
      if !recipe_ok {
         errorf_pos(recipe_name.pos, "Recipe \"{}\" is not defined", recipe_name.str)
         return false
      }
      if !machine_ok {
         errorf_pos(machine_name.pos, "Machine \"{}\" is not defined", machine_name.str)
         return false
      }

      for req_tag in used_tags {
         time, time_ok := defined_tags[req_tag]
         if !time_ok {
            errorf_line(t.pos.line, "Tag {} was not defined in previous lines", req_tag)
            return false
         }
         current_time = max(current_time, time)
      }
      machine_freed := current_recipe[machine] == nil
      for {
         if pqueue.len(next_action_queue) == 0 {
            break
         }

         top := pqueue.peek(next_action_queue)
         if top.time > current_time && machine_freed {
            break
         }
         current_time = max(top.time, current_time)
         pqueue.pop(&next_action_queue)

         recipe_finished := current_recipe[top.machine_id].(^Recipe)
         recipe_finished_count := current_recipe_count[top.machine_id]

         {
            recipe_finished_str := recipe_to_string(recipe_finished^, recipe_finished_count, item_name_unmapping)
            defer delete(recipe_finished_str)
            infof("[{}] Machine {} finished recipe: {}", top.time, machine_id_to_name[top.machine_id], recipe_finished_str)
         }
         for stack in recipe_finished.output {
            inventory[stack.item_id] += recipe_finished_count * stack.count
         }
         current_recipe[top.machine_id] = nil
         if top.machine_id == machine {
            machine_freed = true
         }
      }

      current_recipe[machine] = recipe
      current_recipe_count[machine] = count
      recipe_failed := false
      {
         recipe_str := recipe_to_string(recipe^, count, item_name_unmapping)
         defer delete(recipe_str)
         infof("[{}] Machine {} starts recipe: {}", current_time, machine_id_to_name[machine], recipe_str)
      }
      for stack in recipe.input {
         inventory[stack.item_id] -= count * stack.count
         if inventory[stack.item_id] < 0 {
            errorf_line(t.pos.line, "Missing ingredient \"{}\"", item_name_unmapping[stack.item_id])
            recipe_failed = true
         }
      }
      if recipe_failed {
         return false
      }
      finish_time := current_time + recipe.recipe_time * time.Duration(count)
      pqueue.push(&next_action_queue, PQ_Key{time = finish_time, machine_id = machine})

      if tag_val, tag_val_ok := tag.(string); tag_val_ok {
         defined_tags[tag_val] = finish_time
      }
   }

   for {
      top, top_ok := pqueue.pop_safe(&next_action_queue)
      if !top_ok {
         break
      }

      current_time = max(current_time, top.time)

      recipe_finished := current_recipe[top.machine_id].(^Recipe)
      recipe_finished_count := current_recipe_count[top.machine_id]

      {
         recipe_finished_str := recipe_to_string(recipe_finished^, recipe_finished_count, item_name_unmapping)
         defer delete(recipe_finished_str)
         infof("[{}] Machine {} finished recipe: {}", top.time, machine_id_to_name[top.machine_id], recipe_finished_str)
      }
      for stack in recipe_finished.output {
         inventory[stack.item_id] += recipe_finished_count * stack.count
      }
   }

   for stack in output {
      inventory[stack.item_id] -= stack.count
   }

   for stack in local {
      inventory[stack.item_id] -= stack.count
   }

   recipe_success := true
   for stack, item_id in inventory {
      if stack < 0 {
         errorf_none("Not enough {}", item_name_unmapping[item_id])
         recipe_success = false
      }
      if stack > 0 {
         errorf_none("Excess {}", item_name_unmapping[item_id])
         recipe_success = false
      }
   }

   return recipe_success
}

main :: proc() {
   if !_main() {
      os.exit(1)
   }
}
