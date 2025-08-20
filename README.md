# Building
Requires odin compiler. Build with `make`. Outputs `chemline_verifier` executable.

## Example usage
`./chemline_verifier examples/fecl3.recipe`

## Format / Explanation
We will use `examples/fecl3.recipe` as an example
```
RECIPES
r_fecl3: fe + 3 hcl -> fecl3 + 3h, 30s
r_hcl: h + cl -> hcl, 3s 

MACHINES
cr1
cr2

INPUT
fe
3 cl

OUTPUT
1 fecl3

LOCAL
3 h

PROCESS
1 r_hcl,cr1
2 r_hcl,cr1 -> hcl_done
1 r_fecl3,cr2|hcl_done
```
File is divided into sections: `RECIPES`, `MACHINES`, `INPUT`, `OUTPUT`, `LOCAL` and `PROCESS`.
- `RECIPES` defines recipes that will be used. Format `<recipe name>: <inputs> -> <outputs>, <time>`. `<time>` can be in other units, for example `3m`, `5h`, `2d`, `4t` (`t` stands for tick, 1/20th of a second in minecraft), `3h 3s 6t`
- `MACHINES` each line contains exactly one machine name
- `INPUT`, `OUTPUT`, `LOCAL`: each line contains one type of item with its quantity. If quantity is not specified it is defaulted to 1.
   - `INPUT` means what we will put into the chemical line, `OUTPUT` is what we expect to get out of it after all the processing is done, `LOCAL` means what stays in the chemical line before inputting ingredients and after taking out the output.

- `PROCESS` describes the recipes that will get started **in order**.
   - Format: `<recipe count> <recipe name>, <machine name and required steps> -> <step name>`
   - Or: `<recipe count> <recipe name>, <machine name and required steps>`
   - `<machine name and required steps>` is `<machine_name>|<step name>|<step name>| ...`, there can be any number of required steps, including zero: `<machine_name>`.

Running `./chemline_verifier examples/fecl3.recipe` gives us the following output:
```
[0s] Machine cr1 starts recipe: {Input: 1x h, 1x cl, Output: 1x hcl, Time: 3s}
[3s] Machine cr1 finished recipe: {Input: 1x h, 1x cl, Output: 1x hcl, Time: 3s}
[3s] Machine cr1 starts recipe: {Input: 2x h, 2x cl, Output: 2x hcl, Time: 6s}
[9s] Machine cr1 finished recipe: {Input: 2x h, 2x cl, Output: 2x hcl, Time: 6s}
[9s] Machine cr2 starts recipe: {Input: 1x fe, 3x hcl, Output: 1x fecl3, 3x h, Time: 30s}
[39s] Machine cr2 finished recipe: {Input: 1x fe, 3x hcl, Output: 1x fecl3, 3x h, Time: 30s}
```
- We start at time `0s`
- `1 r_hcl,cr1` can start at `0s` and will finish at `3s`
- It's 0s
- `2 r_hcl,cr1 -> hcl_done` cannot start until `cr1` is freed at `3s`, so we wait until `3s` and schedule it. This recipe will finish, at the `9s` mark, which we've named `hcl_done`.
- It's `3s`
- `1 r_fecl3,cr2|hcl_done` cannot start, because it needs to wait until `hcl_done`, so we wait until `9s` mark and start the recipe.
   - If we would skip the `hcl_done` tag, the recipe would start at `3s` and fail due to lack of `hcl`, in the system there is only 1 unit of `hcl` and the recipe `r_fecl3` need 3 units.

- It's `9s`
- `1 r_fecl3,cr2|hcl_done` is finally finished at `39s`

The recipe started with `3x h`, `1x fe` and `3x cl` and finished with `3x h` and `1x fecl3`. It started with sum of ingredients in `<input>` and `<local>` and finished with sum of ingredients in `<output>` and `<local>`.

This recipe can be optimized, which is shown in `example/fecl3_2.recipe`

```
RECIPES
r_fecl3: fe + 3 hcl -> fecl3 + 3h, 30s
r_hcl: h + cl -> hcl, 3s 

MACHINES
cr1
cr2

INPUT
fe
3 cl

OUTPUT
1 fecl3

LOCAL
3 hcl
3 h

PROCESS
3 r_hcl,cr1
1 r_fecl3,cr2
```

Output:
```
[0s] Machine cr1 starts recipe: {Input: 3x h, 3x cl, Output: 3x hcl, Time: 9s}
[0s] Machine cr2 starts recipe: {Input: 1x fe, 3x hcl, Output: 1x fecl3, 3x h, Time: 30s}
[9s] Machine cr1 finished recipe: {Input: 3x h, 3x cl, Output: 3x hcl, Time: 9s}
[30s] Machine cr2 finished recipe: {Input: 1x fe, 3x hcl, Output: 1x fecl3, 3x h, Time: 30s}
```

Here, both `3 r_hcl,cr1` and `1 r_fecl3,cr2` can be scheduled and process in parallel due to more items in the local storage.