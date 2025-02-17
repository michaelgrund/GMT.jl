const psxy  = plot
const psxy! = plot!
const psxyz  = plot3d
const psxyz! = plot3d!

# ---------------------------------------------------------------------------------------------------
function common_plot_xyz(cmd0::String, arg1, caller::String, first::Bool, is3D::Bool, kwargs...)
	arg2, arg3, arg4 = nothing, nothing, nothing
	N_args = (arg1 === nothing) ? 0 : 1
	is_ternary = (caller == "ternary") ? true : false
	if     (is3D)       gmt_proggy = (IamModern[1]) ? "plot3d "  : "psxyz "
	elseif (is_ternary) gmt_proggy = (IamModern[1]) ? "ternary " : "psternary "
	else		        gmt_proggy = (IamModern[1]) ? "plot "    : "psxy "
	end

	arg1 = df2ds(arg1)							# If arg1 is a DataFrame, try to convert it into a GMTdataset

	d, K, O = init_module(first, kwargs...)		# Also checks if the user wants ONLY the HELP mode
	(!O) && (legend_type[1] = legend_bag())		# Make sure that we always start with an empty one

	cmd::String = "";	sub_module::String = ""	# Will change to "scatter", etc... if called by sub-modules
	opt_A::String = ""							# For the case the caller was in fact "stairs"
	g_bar_fill = Vector{String}()				# May hold a sequence of colors for gtroup Bar plots
	if (caller != "")
		if (occursin(" -", caller))				# some sub-modues use this piggy-backed call to send a cmd
			if ((ind = findfirst("|", caller)) !== nothing)	# A mixed case with "caler|partiall_command"
				sub_module = caller[1:ind[1]-1]
				cmd = caller[ind[1]+1:end]
				caller = sub_module				# Because of parse_BJR()
				(caller == "events") && (gmt_proggy = "events ")
			else
				cmd = caller
				caller = "others"				# It was piggy-backed
			end
		else
			sub_module = caller
			# Needs to be processed here to destinguish from the more general 'fill'
			(caller == "bar") && (g_bar_fill = helper_gbar_fill(d))
			opt_A = (caller == "lines" && ((val = find_in_dict(d, [:stairs_step])[1]) !== nothing)) ? string(val) : ""
		end
	end

	if (occursin('3', caller) && !haskey(d, :p) && !haskey(d, :view) && !haskey(d, :perspective))
		d[:p] = "200/30"		# Need this before parse_BJR() so MAP_FRAME_AXES can be guessed.
	end
	
	isa(arg1, GMTdataset) && (arg1 = with_xyvar(d::Dict, arg1))	# See if we have a column request based on column names

	parse_paper(d)				# See if user asked to temporarily pass into paper mode coordinates

	if (is_ternary)
		opt_B::String = ""
		if (haskey(d, :B))		# Not necessarely the case when ternary!
			cmd, opt_B = cmd * d[:B], d[:B]		# B option was parsed in plot/ternary
			delete!(d, :B)
		end
		cmd, opt_R = parse_R(d, cmd, O)
	end

	if (is_ternary && !first) 	# Either a -J was set and we'll fish it here or no and we'll use the default.
		def_J = " -JX" * split(def_fig_size, '/')[1]
		cmd, opt_J::String = parse_J(d, cmd, def_J)
	else
		def_J = (is_ternary) ? " -JX" * split(def_fig_size, '/')[1] : ""		# Gives "-JX14c" 
		(!is_ternary && isa(arg1, GMTdataset) && length(arg1.ds_bbox) >= 4) && (CTRL.limits[1:4] = arg1.ds_bbox[1:4])
		(!is_ternary && isa(arg1, Vector{<:GMTdataset}) && length(arg1[1].ds_bbox) >= 4) && (CTRL.limits[1:4] = arg1[1].ds_bbox[1:4])
		(!IamModern[1] && haskey(d, :hexbin) && !haskey(d, :aspect)) && (d[:aspect] = :equal)	# Otherwise ... gaps between hexagons
		if (is_ternary)  cmd, opt_J = parse_J(d, cmd, def_J)
		else             cmd, opt_B, opt_J, opt_R = parse_BJR(d, cmd, caller, O, def_J)
		end
	end

	cmd, opt_JZ = parse_JZ(d, cmd)
	cmd, = parse_common_opts(d, cmd, [:a :e :f :g :p :t :w :params], first)
	cmd, opt_l = parse_l(d, cmd)		# Parse this one (legend) aside so we can use it in classic mode
	cmd, opt_f = parse_f(d, cmd)		# Parse this one (-f) aside so we can check against D.attrib
	cmd  = parse_these_opts(cmd, d, [[:D :shift :offset], [:I :intens], [:N :no_clip :noclip]])
	parse_ls_code!(d::Dict)				# Check for linestyle codes (must be before the GMTsyntax_opt() call)
	cmd  = GMTsyntax_opt(d, cmd)		# See if an hardcore GMT syntax string has been passed
	(is_ternary) && (cmd = add_opt(d, cmd, "M", [:M :dump]))
	opt_UVXY = parse_UVXY(d, "")		# Need it separate to not risk to double include it.
	cmd, opt_c = parse_c(d, cmd)		# Need opt_c because we may need to remove it from double calls

	# If the input is a GMTdataset and one of its columns is a Time column, automatically set the -fT
	function set_fT(D::GMTdataset, cmd::String, opt_f::String)
		if ((Tc = get(D.attrib, "Timecol", "")) != "")
			tc = parse(Int, Tc) - 1
			_opt_f = (opt_f == "") ? " -f$(tc)T" : opt_f * ",$(tc)T"
			return (opt_f == "") ? cmd * _opt_f : replace(cmd, opt_f => _opt_f)
		end
		return cmd
	end
	if (isa(arg1, GDtype) && !contains(opt_f, "T") && !contains(opt_f, "t") && !contains(opt_R, "T") && !contains(opt_R, "t"))
		isa(arg1, GMTdataset) && (cmd = set_fT(arg1, cmd, opt_f))
		isa(arg1, Vector{<:GMTdataset}) && (cmd = set_fT(arg1[1], cmd, opt_f))
	end

	# If a file name sent in, read it and compute a tight -R if this was not provided
	got_usr_R = (opt_R != "") ? true : false			# To know if the user set -R or we estimated it from data
	(opt_R == "" && sub_module == "bar") && (opt_R = "/-0.4/0.4/0")		# Make sure y_min = 0
	if (O && caller == "plotyy")
		cmd = replace(cmd, opt_R => "")					# Must remove old opt_R because a new one will be constructed
		ind = collect(findall("/", box_str[1])[2])		# 'box_str' was set in first call
		opt_R = '/' * box_str[1][4:ind[1]] * "?/?"		# Will become /x_min/x_max/?/?
	end

	cmd, arg1, opt_R, _, opt_i = read_data(d, cmd0, cmd, arg1, opt_R, is3D)
	(cmd0 != "" && isa(arg1, GMTdataset)) && (arg1 = with_xyvar(d::Dict, arg1))	# If we read a file, see if requested cols
	(!got_usr_R && opt_R != "") && (CTRL.pocket_R[1] = opt_R)	# Still on time to store it.
	(N_args == 0 && arg1 !== nothing) && (N_args = 1)	# arg1 might have started as nothing and got values above
	(!O && caller == "plotyy") && (box_str[1] = opt_R)	# This needs modifications (in plotyy) by second call

	if (isGMTdataset(arg1) && !isTimecol_in_pltcols(arg1) && getproj(arg1, proj4=true) != "" && opt_J == " -JX" * def_fig_size)
		cmd = replace(cmd, opt_J => " -JX" * split(def_fig_size, '/')[1] * "/0")	# If projected, it's a axis equal for sure
	end
	if (is3D && isempty(opt_JZ) && length(collect(eachmatch(r"/", opt_R))) == 5)
		cmd *= " -JZ6c"		# Default -JZ
		CTRL.pocket_J[3] = " -JZ6c"		# Needed for eventual z-axis dir reversal.
	end

	# Here we check for a direct -A of and indirect via the stairs module.
	cmd = add_opt(d, cmd, "A", [:A :steps :stairs :straight_lines], (x="x", y="y", meridian="m", parallel="p", r="r", theta="t"))
	if (!contains(cmd, " -A") && opt_A != "")	# When the caller is "stairs" 
		if (opt_A == "post")  cmd *= CTRL.proj_linear[1] ? " -Ax" : " -Ap"	# Still leaves out the Polar case
		else                  cmd *= CTRL.proj_linear[1] ? " -Ay" : " -Am"
		end
	end

	opt_F::String = add_opt(d, "", "", [:F :conn :connection],
	                (continuous=("c", nothing, 1), net=("n", nothing, 1), network=("n", nothing, 1), refpoint=("p", nothing, 1),  ignore_hdr="_a", single_group="_f", segments="_s", segments_reset="_r", anchor=("", arg2str)))
	(opt_F != "" && !occursin("/", opt_F)) && (opt_F = string(opt_F[1]))	# Allow con=:net or con=(1,2)
	(opt_F != "") && (cmd *= " -F" * opt_F)

	# Error Bars?
	got_Ebars = false
	val, symb = find_in_dict(d, [:E :error :error_bars], false)
	if (val !== nothing)
		if isa(val, String)
			cmd *= " -E" * val
		else
			cmd, arg1 = add_opt(add_opt, (d, cmd, "E", [symb]),
                                (x="|x",y="|y",xy="|xy",X="|X",Y="|Y", asym="_+a", colored="_+c", cline="_+cl", csymbol="_+cf", notch="|+n", boxwidth="+w", cap="+w", pen=("+p",add_opt_pen)), false, isa(arg1, GMTdataset) ? arg1.data : (isa(arg1, Vector{<:GMTdataset}) ? arg1[1].data : arg1) )
		end
		got_Ebars = true
		del_from_dict(d, [symb])
	end

	# Look for color request. Do it after error bars because they may add a column
	len = length(cmd);	n_prev = N_args;
	opt_Z, args, n, got_Zvars = add_opt(d, "", "Z", [:Z :level :levels], :data, Any[arg1, arg2], (outline="_o", nofill="_f"))
	if (contains(opt_Z, "f") && !contains(opt_Z, "o"))	# Short version. If no fill it must outline otherwise nothing
		do_Z_fill, do_Z_outline = false, true;		opt_Z = replace(opt_Z, "f" => "")
	else
		(!contains(opt_Z, "f")) ? do_Z_fill = true : (do_Z_fill = false; opt_Z = replace(opt_Z, "f" => ""))
		(contains(opt_Z, "o")) ? (do_Z_outline = true; opt_Z = replace(opt_Z, "o" => "")) : (do_Z_outline = false)
	end
	(opt_Z != "") && (cmd *= opt_Z)
	(!got_Zvars) && (do_Z_fill = do_Z_outline = false)	# Because the may have wrongly been set above

	if (n > 0)
		if (GMTver <= v"6.3")					# -Z is f again. Must save data into file to make it work.
			fname = joinpath(tempdir(), "GMTjl_temp_Z.txt")
			fid = open(fname, "w")
			for k = 1:length(args[n])  println(fid, args[n][k])  end;	close(fid)
			cmd *= fname
		else
			arg1, arg2 = args[:]
			N_args = n
		end
	end
	in_bag = (got_Zvars || haskey(d, :hexbin)) ? true : false		# Other cases should add to this list
	opt_T::String = (haskey(d, :hexbin)) ? @sprintf(" -T%s/%s/%d+n",arg1.bbox[5], arg1.bbox[6], 65) : ""
	if (N_args < 2)
		cmd, arg1, arg2, N_args = add_opt_cpt(d, cmd, CPTaliases, 'C', N_args, arg1, arg2, true, true, opt_T, in_bag)
	else			# Here we know that both arg1 & arg2 are already occupied, so must use arg3 only
		cmd, arg3, = add_opt_cpt(d, cmd, CPTaliases, 'C', 0, arg3, nothing, true, true, opt_T, in_bag)
		N_args = 3
	end

	# Need to parse -W here because we need to know if the call to make_color_column() MUST be avoided. 
	opt_W::String = add_opt_pen(d, [:W :pen], "W")
	arg1, opt_W, got_color_line_grad, made_it_vector = _helper_psxy_line(d, cmd, opt_W, is3D, arg1, arg2, arg3)

	mcc, bar_ok = false, (sub_module == "bar" && !check_bar_group(arg1))
	if (!got_color_line_grad && (arg1 !== nothing && !isa(arg1, GMTcpt)) && ((!got_Zvars && !is_ternary) || bar_ok))
		# If "bar" ONLY if not bar-group
		# See if we got a CPT. If yes there may be some work to do if no color column provided in input data.
		cmd, arg1, arg2, N_args, mcc = make_color_column(d, cmd, opt_i, len, N_args, n_prev, is3D, got_Ebars, bar_ok, g_bar_fill, arg1, arg2)
	end

	opt_G::String = ""
	if (isempty(g_bar_fill))					# Otherwise bar fill colors are dealt with somewhere else
		((opt_G = add_opt_fill("", d, [:G :fill], 'G')) != "") && (cmd *= opt_G)	# Also keep track if -G was set
	end
	opt_Gsymb::String = add_opt_fill("", d, [:G :mc :markercolor :markerfacecolor :MarkerFaceColor], 'G')	# Filling of symbols
	(opt_Gsymb == " -G") && (opt_Gsymb *= "black")	# Means something like 'mc=true' was used, but we need a color

	opt_L::String = ""
	if (is_ternary)				# Means we are in the psternary mode
		cmd = add_opt(d, cmd, "L", [:L :vertex_labels])
	else
		opt_L = add_opt(d, "", "L", [:L :close :polygon],
		                (left="_+xl", right="_+xr", x0="+x", bot="_+yb", top="_+yt", y0="+y", sym="_+d", asym="_+D", envelope="_+b", pen=("+p",add_opt_pen)))
		(length(opt_L) > 3 && !occursin("-G", cmd) && !occursin("+p", cmd)) && (opt_L *= "+p0.5p")
		cmd *= opt_L
	end

	if ((val = find_in_dict(d, [:decorated])[1]) !== nothing)
		cmd = (isa(val, String)) ? cmd * " " * val : cmd * decorated(val)
		if (occursin("~f:", cmd) || occursin("qf:", cmd))	# Here we know val is a NT and `locations` was numeric
			_, arg1, arg2, arg3 = arg_in_slot(nt2dict(val), "", [:locations], Union{Matrix, GDtype}, arg1, arg2, arg3)
		end
	end

	opt_Wmarker::String = ""
	if ((val = find_in_dict(d, [:mec :markeredgecolor :MarkerEdgeColor])[1]) !== nothing)
		tmec::String = arg2str(val)
		!contains(tmec, "p,") && (tmec = "0.5p," * tmec)	# If not provided, default to a line thickness of 0.5p
		opt_Wmarker = tmec
	end

	# This bit is for the -Z option. Must consolidate the options.
	(do_Z_fill && opt_G == "") && (cmd *= " -G+z")
	(do_Z_outline && !contains(opt_W, "+z")) && (opt_W = (opt_W == "") ? " -W0.5+z" : opt_W * "+z")
	(got_Zvars && !do_Z_fill && !do_Z_outline && opt_W == "") && (opt_W = " -W0.5+z")	# Nofill and nothing else defaults to -W+z
	(got_Zvars && (do_Z_fill || opt_G != "") && opt_L == "") && (cmd *= " -L")	# GMT requires -L when -Z fill or -G

	if ((do_Z_fill || do_Z_outline || (got_color_line_grad && !is3D)) && !occursin("-C", cmd))
		if (isempty(current_cpt[1]))
			if (got_color_line_grad)		# Use the fact that we have min/max already stored
				mima::Vector{Float64} = (arg1.ds_bbox[5+2*is3D], arg1.ds_bbox[6+2*is3D])
			else
				mima = [extrema(last_non_nothing(arg1, arg2, arg3))...]	# Why 'last'?
			end
			r = makecpt(@sprintf("-T%f/%f/65+n -Cturbo -Vq", mima[1]-eps(1e10), mima[2]+eps(1e10)))
		else
			r = current_cpt[1]
		end
		(arg1 === nothing) ? arg1 = r : ((arg2 === nothing) ? arg2 = r : (arg3 === nothing ? arg3 = r : arg4 = r))
		cmd *= " -C"
	end

	arg1, opt_S = parse_opt_S(d, arg1, is3D)

	opt_ML::String = ""
	if (opt_S != "")
		opt_ML, opt_Wmarker = parse_markerline(d, opt_ML, opt_Wmarker)
	end
	(made_it_vector && opt_S == "") && (cmd *= " -Sv+s")	# No set opt_S because it results in 2 separate commands

	# See if any of the scatter, bar, lines, etc... was the caller and if yes, set sensible defaults.
	cmd  = check_caller(d, cmd, opt_S, opt_W, sub_module, g_bar_fill, O)
	(mcc && caller == "bar" && !got_usr_R && opt_R != " -R") && (cmd = recompute_R_4bars!(cmd, opt_R, arg1))	# Often needed
	_cmd = build_run_cmd(cmd, opt_B, opt_Gsymb, opt_ML, opt_S, opt_W, opt_Wmarker, opt_UVXY, opt_c)

	(got_Zvars && opt_S == "" && opt_W == "" && !occursin(" -G", _cmd[1])) && (_cmd[1] *= " -W0.5")
	(opt_W == "" && caller == "feather") && (_cmd[1] *= " -W0.1")		# feathers are normally many so better they are thin

	# Let matrices with more data columns, and for which Color info was NOT set, plot multiple lines at once
	arg1, _cmd = helper_multi_cols(d, arg1, mcc, opt_R, opt_S, opt_W, caller, is3D, multi_col, _cmd,
	                               sub_module, g_bar_fill, got_Ebars, got_usr_R)

	# Try to limit the damage of this Fker bug in 6.2.0
	if ((mcc || got_Ebars) && (GMTver == v"6.2.0" && isGMTdataset(arg1) && occursin(" -i", cmd)) )
		if (isa(arg1, GMTdataset))	arg1 = arg1.data
		elseif (isa(arg1, Vector{<:GMTdataset}))
			(length(arg1) > 1) && @warn("Due to a bug in GMT6.2.0 I'm forced to use only the first segment")
			arg1 = arg1[1].data
		end
	end

	(!IamModern[1]) && put_in_legend_bag(d, _cmd, arg1, O, opt_l)

	_cmd = gmt_proggy .* _cmd				# In any case we need this
	_cmd = finish_PS_nested(d, _cmd)
	_cmd = fish_bg(d, _cmd)					# See if we have a "pre-command"

	finish = (is_ternary && occursin(" -M",_cmd[1])) ? false : true		# But this case (-M) is bugged still in 6.2.0
	r = finish_PS_module(d, _cmd, "", K, O, finish, arg1, arg2, arg3, arg4)
	(occursin("-Sk", opt_S)) && gmt_restart()  # Apparently patterns & custom symbols are screwing the session
	return r
end

# ---------------------------------------------------------------------------------------------------
function with_xyvar(d::Dict, arg1::GMTdataset, no_x::Bool=false)
	# Make a subset of a GMTdataset by selecting which coluns to extract. The selection can be done by
	# column numbers or column names. 'xvar' selects only the xx col, but 'yvar' can select more than one.
	# 'no_x' is for croping some columns and not add a x column and not split in many D's (one per column).
	# By default when yvar is a vec we split the columns by default (WHY??). Pass nomulticol=1 in `d` to prevent this.
	((val_y = find_in_dict(d, [:yvar])[1]) === nothing) && return arg1	# No y colname, no business
	ycv::Vector{Int}, ismulticol = Int[], false
	if (isa(val_y, Integer) || isa(val_y, String) || isa(val_y, Symbol))
		yc = isa(val_y, Integer) ? val_y : ((ind = findfirst(string(val_y) .== arg1.colnames)) !== nothing ? ind : 0)
		(yc < 1 || yc > size(arg1,2)) && error("'yvar' Name not found in GMTdataset col names or exceed col count.")
		ycv = [yc]
	elseif (isvector(val_y) || isa(val_y, Tuple))
		if (eltype(val_y) <: Integer)
			ycv = [val_y...]
		elseif (eltype(val_y) <: Union{String, Symbol})
			vs = [string.(val_y)...]
			ycv = zeros(Int, length(vs))
			for k = 1:lastindex(vs)
				((ind = findfirst(vs[k] .== arg1.colnames)) !== nothing) && (ycv[k] = ind)
			end
			any(ycv .== 0) && error("One or more column names does not match with data colnames.")
		end
		isempty(ycv) && error("yvar option is non-sense.")
		(minimum(ycv) < 1 || maximum(ycv) > size(arg1,2)) && error("Col names not found in GMTdataset col names or exceed col count.")
		domulticol = ((val = find_in_dict(d::Dict, [:nomulticol])[1]) === nothing) ? true : false
		(domulticol) && (ismulticol = true)
	end

	function getcolvar(d::Dict, var::VMs)
		((val = find_in_dict(d::Dict, var)[1]) === nothing) && return nothing
		!(isa(val, Integer) || isa(val, String) || isa(val, Symbol)) && error("$(var) can only be an Int, a String or a Symbol but was a $(typeof(val))")
		c = isa(val, Integer) ? val : ((ind = findfirst(string(val) .== arg1.colnames)) !== nothing ? ind : 0)
		(c < 1 || c > size(arg1,2)) && error("$(var) Col name not found in GMTdataset col names or exceed col count.")
		c
	end

	xc = getcolvar(d, [:xvar])
	((zc = getcolvar(d, [:zvar])) !== nothing) && (ycv = [ycv..., zc])
	((sc = getcolvar(d, [:svar :szvar :sizevar])) !== nothing) && (ycv = [ycv..., sc])
	((cc = getcolvar(d, [:cvar :colorvar])) !== nothing) && (ycv = [ycv..., cc])
	if (!no_x)
		if (xc === nothing)
			out = mat2ds(hcat(collect(1:size(arg1,1)), arg1.data[:, ycv]))
			out.colnames = append!(["X"], arg1.colnames[ycv])
			if ((Tc = get(arg1.attrib, "Timecol", "")) != "")	# Try to keep also an eventual Timecol
				((ind = findfirst(parse(Int, Tc) .== ycv)) !== nothing) && (D.attrib[:Timecol] = (xc !== nothing) ? ind+1 : ind)
			end
		else
			out = mat2ds(arg1, (:, [xc, ycv...]))
		end
		#D = (ismulticol) ? mat2ds(out, multi=true, color=:cycle) : mat2ds(out)		# Return a GMTdataset
		if (ismulticol)
			D = mat2ds(out.data, multi=true, color=:cycle)
			if ((Tc = get(arg1.attrib, "Timecol", "")) == "1")	# Try to keep an eventual Timecol
				for k = 1:numel(D)  D[k].attrib["Timecol"] = "1";	D[k].colnames[1] = "Time";  end
			end
		else
			D = out
		end
	else
		D = mat2ds(arg1, (:,ycv))
	end
	return D
end

# ---------------------------------------------------------------------------------------------------
function fish_bg(d::Dict, cmd::Vector{String})
	# Check if the background image is used and if yes insert a first command that calls grdimage to fill
	# the canvas with that bg image. The BG image can be a file name, the name of one of the pre-defined
	# functions, or a GMTgrid/GMTimage object.
	# By default we use a trimmed gray scale (between ~64 & 240) but if user wants to control the colormap
	# then the option's argument can be a tuple where the second element is cpt name or a GMTcpt obj.
	# Ex:  plot(rand(8,2), bg=(:somb, :turbo), show=1)
	# To revert the sense of the color progression prefix the cpt name or of the pre-def function with a '-'
	# Ex: plot(rand(8,2), bg="-circ", show=1)
	((val = find_in_dict(d, [:bg :background])[1]) === nothing) && return cmd
	arg1, arg2 = isa(val, Tuple) ? val[:] : (val, nothing)
	(arg2 !== nothing && (!isa(arg2, GMTcpt) && !isa(arg2, StrSymb))) &&error("When a Tuple is used in argument of the background image option, the second element must be a string or a GMTcpt object.")
	gotfname, fname::String, opt_I::String = false, "", ""
	if (isa(arg1, StrSymb))
		if (splitext(string(arg1))[2] != "")		# Assumed to be an image file name
			fname, gotfname = arg1, true
		else										# A pre-set fun name
			fun::String = string(arg1)
			(fun[1] == '-') && (fun = fun[2:end]; opt_I = " -I")
			I::GMTimage = imagesc(mat2grid(fun))
		end
	elseif (isa(arg1, GMTgrid) || isa(arg1, GMTimage))
		I = isa(arg1, GMTgrid) ? imagesc(arg1) : val
	end
	if (!gotfname)
		((arg2 !== nothing) && isa(arg2, String) && (arg2[1] == '-')) && (arg2 = arg2[2:end]; opt_I = " -I")
		opt_H = (IamModern[1]) ? " -H" : ""
		C::GMTcpt = (arg2 === nothing) ? gmt("makecpt -T0/256/1 -G0.25/0.94 -Cgray"*opt_I*opt_H) :	# The default gray scale
		                                 isa(arg2, GMTcpt) ? gmt("makecpt -T0/256/1 -C" * opt_H, arg2) :
							        	 gmt("makecpt -T0/256/1 -C" * string(arg2) * opt_I * opt_H)
		image_cpt!(I, C)
		CTRL.pocket_call[3] = I					# This signals finish_PS_module() to run _cmd first
	end

	opt_p = scan_opt(cmd[1], "-p");		(opt_p != "") && (opt_p = " -p" * opt_p)
	opt_c = scan_opt(cmd[1], "-c");		(opt_c != "") && (opt_c = " -c" * opt_c)
	#(opt_c == "" && contains(cmd[1], " -c ")) && (opt_c = " -c")	# Because of a scan_opt() desing error (but causes error)
	opt_D = (IamModern[1]) ? " -Dr " : " -D "	# Found this difference by experience. It might break in future GMTs
	["grdimage" * opt_D * fname * CTRL.pocket_J[1] * opt_p * opt_c, cmd...]
end

# ---------------------------------------------------------------------------------------------------
function isTimecol_in_pltcols(D::GDtype)
	# See if we have a Timecol in one of the ploting columns
	(isa(D, GMTdataset) && ((Tc = get(D.attrib, "Timecol", "")) == "")) && return false
	(isa(D, Vector{<:GMTdataset}) && ((Tc = get(D[1].attrib, "Timecol", "")) == "")) && return false
	tc = parse(Int, Tc)
	return (tc <= 2) ? true : false
end

# ---------------------------------------------------------------------------------------------------
function _helper_psxy_line(d, cmd, opt_W, is3D, args...)
	haskey(d, :multicol) && return args[1], opt_W, false, false	# NOT OBVIOUS IF THIS IS WHAT WE WANT TO DO
	got_color_line_grad, got_variable_lt, made_it_vector, rep_str = false, false, false, ""
	(contains(opt_W, ",gradient") || contains(opt_W, ",grad")) && (got_color_line_grad = true)

	if (got_color_line_grad)
		if (occursin("-C", cmd))
			cpt = get_first_of_this_type(GMTcpt, args...)
			if (cpt === nothing)
				CPTname = scan_opt(cmd, "-C")
				cpt = gmtread(CPTname, cpt=true)
			end
		elseif (!isempty(current_cpt[1]))
			cpt = current_cpt[1]
		else
			mima = (size(args[1],2) == 2) ? (1,size(args[1],1)) : (args[1].ds_bbox[5+0*is3D], args[1].ds_bbox[6+0*is3D])
			cpt = makecpt(@sprintf("-T%f/%f/65+n -Cturbo -Vq", mima[1]-eps(1e10), mima[2]+eps(1e10)))
		end
	end

	# If we get a line thickness variation we must always call line2multiseg(). The :var_lt was set in build_pen()
	((val = find_in_dict(d, [:var_lt])[1]) !== nothing) && (got_variable_lt = true)

	if (got_color_line_grad && !got_variable_lt)
		if (!is3D)
			arg1 = mat2ds(color_gradient_line(args[1], is3D=is3D))
			made_it_vector, rep_str = true, "+cl"
		else
			arg1 = line2multiseg(args[1], is3D=true, color=cpt)
		end
	elseif (got_variable_lt)	# Otherwise just return without doing anything
		if (got_color_line_grad)  arg1 = line2multiseg(args[1], is3D=is3D, lt=vec(val), color=cpt)
		else                      arg1 = line2multiseg(args[1], is3D=is3D, lt=vec(val))
		end
	else
		arg1 = args[1]			# Means this function call did nothing
	end
	contains(opt_W, ",gradient") && (opt_W = replace(opt_W, ",gradient" => rep_str))
	contains(opt_W, ",grad")     && (opt_W = replace(opt_W, ",grad" => rep_str))
	(opt_W == " -W") && (opt_W = "")	# All -W options are set in dataset headers, so no need for -W
	return arg1, opt_W, got_color_line_grad, made_it_vector
end

# ---------------------------------------------------------------------------------------------------
function parse_opt_S(d, arg1, is3D)

	opt_S::String = ""
	# First see if the requested symbol is a custom one from GMT.jl share/custom
	if ((symb = is_in_dict(d, [:csymbol :cmarker :custom_symbol :custom_marker])) !== nothing)
		marca::String = add_opt(d, "", "", [symb], (name="", size="/", unit="1"))
		marca_fullname, marca_name = seek_custom_symb(marca)
		(marca_name != "") && (opt_S = " -Sk" * marca_fullname)
	else
		opt_S = add_opt(d, "", "S", [:S :symbol], (symb="1", size="", unit="1"))
	end

	if (opt_S == "")			# OK, no symbol given via the -S option. So fish in aliases
		marca, arg1, more_cols = get_marker_name(d, arg1, [:marker, :Marker, :shape], is3D, true)
		if ((val = find_in_dict(d, [:ms :markersize :MarkerSize :size])[1]) !== nothing)
			(marca == "") && (marca = "c")		# If a marker name was not selected, defaults to circle
			#val_::VecOrMat{<:Real} = is_this_type(VecOrMat{<:Real}, val) ? val : VecOrMat{<:Real}[]
			#val_ = isa(val, VMr) ? val : VMr[]
			if (isa(val, VMr))
				val_::VMr = val
				if (length(val_) == 2)			# A two elements array is interpreted as [min max]
					scale = (eltype(val_) <: Integer) ? 2.54/72 : 1.0	# In integers, assumes they are points
					arg1 = hcat(arg1, linspace(val[1], val_[2], size(arg1,1)).*scale)
				else
					(length(val_) != size(arg1,1)) &&
						error("The size array must have the same number of elements as rows in data")
					arg1 = hcat(arg1, val_[:])
				end
			elseif (isa(val, Tuple) && isa(val[1], Function) && isa(val[2], VMr))
				val2::Tuple = val
				scale = (eltype(val2[2]) <: Integer) ? 2.54/72 : 1.0
				ind = sortperm(funcurve(val2[1], val2[2].*scale, size(arg1,1)))	# Get the sorting indices
				arg1 = hcat(arg1, is3D ? view(arg1,:,3)[ind] : view(arg1,:,2)[ind])
			elseif (string(val) != "indata")	# WTF is "indata"?
				marca *= arg2str(val)
			end
			opt_S = " -S" * marca
		elseif (marca != "")					# User only selected a marker name but no size.
			opt_S = " -S" * marca
			# If data comes from a file, then no automatic symbol size is added
			op = lowercase(marca[1])
			def_size = (op == 'p') ? "2p" : "7p"	# 'p' here stands for symbol points, not units
			(!more_cols && arg1 !== nothing && !isa(arg1, GMTcpt) && !occursin(op, "bekmrvw")) && (opt_S *= def_size)
		elseif (haskey(d, :hexbin))
			inc::Float64 = parse(Float64, arg1.attrib["hexbin"])
			r = (CTRL.limits[8] - CTRL.limits[7]) / sqrt(3) / inc
			(CTRL.figsize[1] == 0) && @warn("Failed to automatically fetch the fig width. Using 14 cm to show something.")
			w = (CTRL.figsize[1] != 0) ? CTRL.figsize[1] : 14
			opt_S = " -Sh$(w / (r * 1.5))"		# Is it always 1.5?
			delete!(d, :hexbin)
		end
	else
		val, symb = find_in_dict(d, [:ms :markersize :MarkerSize :size])
		(val !== nothing) && @warn("option *$(symb)* is ignored when either *S* or *symbol* options are used")
		val, symb = find_in_dict(d, [:marker :Marker :shape])
		(val !== nothing) && @warn("option *$(symb)* is ignored when either *S* or *symbol* options are used")
	end
	return arg1, opt_S
end

# ---------------------------------------------------------------------------------------------------
function parse_markerline(d::Dict, opt_ML::String, opt_Wmarker::String)::Tuple{String, String}
	# Make this code into a function so that it can also be called from mk_styled_line!()
	if ((val = find_in_dict(d, [:ml :markerline :MarkerLine])[1]) !== nothing)
		if (isa(val, Tuple))           opt_ML = " -W" * parse_pen(val) # This can hold the pen, not extended atts
		elseif (isa(val, NamedTuple))  opt_ML = add_opt_pen(nt2dict(val), [:pen], "W")
		else                           opt_ML = " -W" * arg2str(val)
		end
		if (opt_Wmarker != "")
			@warn("markerline overrides markeredgecolor");		opt_Wmarker = ""
		end
	end
	return opt_ML, opt_Wmarker
end

# ---------------------------------------------------------------------------------------------------
function build_run_cmd(cmd, opt_B, opt_Gsymb, opt_ML, opt_S, opt_W, opt_Wmarker, opt_UVXY, opt_c)::Vector{String}
	# Build the executble command vector
	if (opt_W != "" && opt_S == "") 						# We have a line/polygon request
		_cmd = [cmd * opt_W * opt_UVXY]

	elseif (opt_W == "" && (opt_S != "" || opt_Gsymb != ""))	# We have a symbol request
		(opt_Wmarker != "" && opt_W == "") && (opt_Gsymb *= " -W" * opt_Wmarker)	# reuse var name
		(opt_ML != "") && (cmd *= opt_ML)					# If we have a symbol outline pen
		_cmd = [cmd * opt_S * opt_Gsymb * opt_UVXY]

	elseif (opt_W != "" && opt_S != "")						# We have both line/polygon and a symbol
		(occursin(opt_Gsymb, cmd)) && (opt_Gsymb = "")
		if (opt_S[4] == 'v' || opt_S[4] == 'V' || opt_S[4] == '=')
			_cmd = [cmd * opt_W * opt_S * opt_Gsymb * opt_UVXY]
		else
			(opt_Wmarker != "") && (opt_Wmarker = " -W" * opt_Wmarker)		# Set Symbol edge color
			cmd1 = cmd * opt_W * opt_UVXY
			(opt_B != " " && opt_B != "") && (cmd = replace(cmd, opt_B => ""))	# Some themes make opt_B = " "
			cmd2 = cmd * opt_S * opt_Gsymb * opt_Wmarker	# Don't repeat option -B
			(opt_c != "")  && (cmd2 = replace(cmd2, opt_c => ""))  				# Not in scond call (subplots)
			(opt_ML != "") && (cmd2 = cmd2 * opt_ML)				# If we have a symbol outline pen
			_cmd = [cmd1; cmd2]
		end

	else
		_cmd = [cmd * opt_UVXY]
	end
end

# ---------------------------------------------------------------------------------------------------
function helper_multi_cols(d::Dict, arg1, mcc, opt_R, opt_S, opt_W, caller, is3D, multi_col, _cmd, sub_module, g_bar_fill, got_Ebars, got_usr_R)
	# Let matrices with more data columns, and for which Color info was NOT set, plot multiple lines at once
	if (!mcc && opt_S == "" && (caller == "lines" || caller == "plot") && isa(arg1, Matrix{<:Real}) &&
		                        size(arg1,2) > 2+is3D && size(arg1,1) > 1 && (multi_col[1] || haskey(d, :multicol)))
		penC, penS = "", "";	multi_col[1] = false	# Reset because this is a use-only-once option
		(haskey(d, :multicol)) && delete!(d, :multicol)
		# But if we have a color in opt_W (idiotic) let it overrule the automatic color cycle in mat2ds()
		penT = ""
		if     (opt_W != "")                penT, penC, penS = break_pen(scan_opt(opt_W, "-W"))
		elseif (!occursin(" -W", _cmd[1]))  _cmd[1] *= " -W0.5"
		end
		arg1 = (penT != "") ? mat2ds(arg1, color = (penC != "") ? [penC] : :cycle, lt=penT, ls=penS, multi=true) :
		                             mat2ds(arg1, color = (penC != "") ? [penC] : :cycle, ls=penS, multi=true)
		mat::Matrix{<:Float64} = gmt("gmtinfo -C", arg1).data		# But now also need to update the -R string
		_cmd[1] = replace(_cmd[1], opt_R => " -R" * arg2str(round_wesn(mat)))
	elseif (!mcc && sub_module == "bar" && check_bar_group(arg1))	# !mcc because the bar-groups all have mcc = false
		_cmd[1], arg1, cmd2 = bar_group(d, _cmd[1], opt_R, g_bar_fill, got_Ebars, got_usr_R, arg1)
		(cmd2 != "") && (length(_cmd) == 1 ? (_cmd = [cmd2; _cmd[1]]) : (@warn("Can't plot the connector when 'bar' is already a nested call."); CTRL.pocket_call[3] = nothing))
	end
	return arg1, _cmd
end

# ---------------------------------------------------------------------------------------------------
function helper_gbar_fill(d::Dict)::Vector{String}
	# This is a function that tryies to hammer the insistence that g_bar_fill is a Any
	# g_bar_fill may hold a sequence of colors for group Bar plots
	gval = find_in_dict(d, [:fill :fillcolor], false)[1]	# Used for group colors
	if (isa(gval, Array{String}) && length(gval) > 1)
		g_bar_fill::Vector{String} = String[]
		append!(g_bar_fill, gval)
	elseif ((isa(gval, Array{Int}) || isa(gval, Tuple) && eltype(gval) == Int) && length(gval) > 1)
		g_bar_fill = Vector{String}(undef, length(gval))			# Patterns
		for k in eachindex(gval)  g_bar_fill[k] = string('p', gval[k])  end
	elseif (isa(gval, Tuple) && (eltype(gval) == String || eltype(gval) == Symbol) && length(gval) > 1)
		g_bar_fill = Vector{String}(undef, length(gval))			# Patterns
		for k in eachindex(gval)  g_bar_fill[k] = string(gval[k])  end
	else
		g_bar_fill = String[]		# To have somthing to return
	end
	return g_bar_fill
end

# ---------------------------------------------------------------------------------------------------
# Check if a group bar request or just bars. Returns TRUE in first case and FALSE in second
check_bar_group(arg1) = ( (isa(arg1, Matrix{<:Real}) || eltype(arg1) <: GMTdataset) &&
                          (isa(arg1, Vector{<:GMTdataset}) ? size(arg1[1],2) > 2 : size(arg1,2) > 2) )::Bool

# ---------------------------------------------------------------------------------------------------
function bar_group(d::Dict, cmd::String, opt_R::String, g_bar_fill::Array{String}, got_Ebars::Bool, got_usr_R::Bool, arg1)
	# Convert input array into a multi-segment Dataset where each segment is an element of a bar group
	# Example, plot two groups of 3 bars each: bar([0 1 2 3; 1 2 3 4], xlabel="BlaBla")

	cmd2::String = ""			# Only used in the waterfall case to hold the 'connector' command
	if (got_Ebars)
		opt_E = scan_opt(cmd, "-E")
		((ind  = findfirst("+", opt_E)) !== nothing) && (opt_E = opt_E[1:ind[1]-1])	# Strip eventual modifiers
		(((ind = findfirst("X", opt_E)) !== nothing) || ((ind = findfirst("Y", opt_E)) !== nothing)) && return cmd, arg1
		n_xy_bars = (findfirst("x", opt_E) !== nothing) + (findfirst("y", opt_E) !== nothing)
		n_cols = size(arg1,2)
		((n_cols - n_xy_bars) == 2) && return cmd, arg1			# Only one-bar groups
		(iseven(n_cols)) && error("Wrong number of columns in error bars array (or prog error)")
		n = Int((n_cols - 1) / 2)
		_arg = Float64.(arg1[:, 1:(n+1)])	# No need to care with GMTdatasets because case was dealt in 'got_Ebars'
		bars_cols = arg1[:,(n + 2):end]		# We'll use this to appent to the multi-segments
	else
		_arg = isa(arg1, GMTdataset) ? Float64.(copy(arg1.data)) : (isa(arg1, Vector{<:GMTdataset}) ? Float64.(copy(arg1[1].data)) : Float64.(copy(arg1)))
		bars_cols = missing
	end

	do_multi = true;	is_stack = false		# True for grouped; false for stacked groups
	is_waterfall = false
	is_hbar = occursin("-SB", cmd)				# An horizontal bar plot

	if ((val = find_in_dict(d, [:stack :stacked])[1]) !== nothing)
		# Take this (two groups of 3 bars) [0 1 2 3; 1 2 3 4]  and compute this (the same but stacked)
		# [0 1 0; 0 3 1; 0 6 3; 1 2 0; 1 5 2; 1 9 4]
		# Taking for example the first group, [0 1 0; 0 3 1; 0 6 3] this means:
		# [|x=0 base=0, y=1|; |x=0 base=1, y=3|; |x=0, base=3, y=6]
		is_waterfall = startswith(string(val), "water")
		nl::Int = size(_arg,2)-1				# N layers in stack
		tmp = zeros(size(_arg,1)*nl, 3)

		for m = 1:size(_arg, 1)			# Loop over number of groups
			tmp[(m-1)*nl+1,1] = _arg[m,1];		tmp[(m-1)*nl+1,2] = _arg[m,2];	# 3rd col is zero
			for n = 2:nl				# Loop over number of layers (n bars in a group)
				tmp[(m-1)*nl+n,1] = _arg[m,1]
				if (sign(tmp[(m-1)*nl+n-1,2]) == sign(_arg[m,n+1]))		# When we have neg & pos, case is diff
					tmp[(m-1)*nl+n,2] = tmp[(m-1)*nl+n-1,2] + _arg[m,n+1]
					tmp[(m-1)*nl+n,3] = tmp[(m-1)*nl+n-1,2]
				else
					if (is_waterfall)
						tmp[(m-1)*nl+n,3] = tmp[(m-1)*nl+n-1,2]
						tmp[(m-1)*nl+n,2] = tmp[(m-1)*nl+n,3] + _arg[m,n+1]
						(tmp[(m-1)*nl+n,2] == tmp[(m-1)*nl+n,3]) && (tmp[(m-1)*nl+n,3] = 0)		# A 'total' column
					else
						tmp[(m-1)*nl+n,2] = _arg[m,n+1]
						tmp[(m-1)*nl+n,3] = 0
					end
				end
			end
		end
		if (is_waterfall)
			for k = 2:nl  tmp[k] += (k-1)  end			# Set the x coordinates of each bar

			tricol = ["darkgreen", "tomato", "gray70"]	# The default colors when no other were sent in args
			if (!isempty(g_bar_fill))					# Bar colors sent in as args to this function.
				tricol[1:2] = string.(g_bar_fill[1:2])	# If < 2 it will error
				(length(g_bar_fill) > 2) && (tricol[3] = string(g_bar_fill[3]))
			end
			g_bar_fill = fill(tricol[1], nl)
			g_bar_fill[_arg[2:end] .< 0]  .= tricol[2]
			g_bar_fill[_arg[2:end] .== 0] .= tricol[3]

			if (is_in_dict(d, [:connector]) !== nothing)
				# Here we need to know the bar width but that info was fetch in check_caller. So fish it from -Sb0.8u+b0
				bw  = parse(Float64, split(split(split(cmd, "-S")[2])[1], "u+")[1][2:end])
				bw2 = bw / 2
				con = fill(NaN, (nl-1)*3, 2)
				for k = 1:nl-1
					con[(k-1)*3+1:(k-1)*3+2, :] = [tmp[k]+bw2 tmp[k,2]; tmp[k+1]-bw2 tmp[k+1,3]]
					(_arg[k+2] == 0) && (con[(k-1)*3+2, 2] = tmp[k+1,2])	# 'total' bars are always 0->top
				end
				CTRL.pocket_call[3] = con
				cmd2 = add_opt_pen(d, [:connector], "W")
			end
		end
		(is_hbar) && (tmp = [tmp[:,2] tmp[:,1] tmp[:,3]])		# Horizontal bars must swap 1-2 cols
		_arg = tmp
		do_multi = false;		is_stack = true
	end

	if ((isempty(g_bar_fill) || is_waterfall) && findfirst("-G0/115/190", cmd) !== nothing)		# Remove auto color
		cmd = replace(cmd, " -G0/115/190" => "")
	end

	# Convert to a multi-segment GMTdataset. There will be as many segments as elements in a group
	# and as many rows in a segment as the number of groups (number of bars if groups had only one bar)
	alpha = find_in_dict(d, [:alpha :fillalpha :transparency])[1]
	_argD::Vector{GMTdataset{eltype(_arg), 2}} = mat2ds(_arg; fill=g_bar_fill, multi=do_multi, fillalpha=alpha, letsingleton=true)
	(is_stack) && (_argD = ds2ds(_argD[1], fill=g_bar_fill, color_wrap=nl, fillalpha=alpha))
	if (is_hbar && !is_stack)					# Must swap first & second col
		for k = 1:lastindex(_argD)  _argD[k].data = [_argD[k].data[:,2] _argD[k].data[:,1]]  end
	end
	(!isempty(g_bar_fill)) && delete!(d, :fill)

	if (bars_cols !== missing)		# Loop over number of bars in each group and append the error bar
		for k = 1:lastindex(_argD)
			_argD[k].data = reshape(append!(_argD[k].data[:], bars_cols[:,k]), size(_argD[k].data,1), :)
		end
	end

	# Must fish-and-break-and-rebuild -S option
	opt_S = scan_opt(cmd, "-S")
	sub_b = ((ind = findfirst("+", opt_S)) !== nothing) ? opt_S[ind[1]:end] : ""	# The +Base modifier
	(sub_b != "") && (opt_S = opt_S[1:ind[1]-1])	# Strip it because we need to (re)find Bar width
	bw::Float64 = (isletter(opt_S[end])) ? parse(Float64, opt_S[3:end-1]) : parse(Float64, opt_S[2:end])	# Bar width
	n_in_group = length(_argD)						# Number of bars in the group
	new_bw::Float64 = (is_stack) ? bw : bw / n_in_group	# 'width' does not change in bar-stack
	new_opt_S = "-S" * opt_S[1] * "$(new_bw)u"
	cmd = (is_stack) ? replace(cmd, "-S"*opt_S*sub_b => new_opt_S*"+b") : replace(cmd, "-S"*opt_S => new_opt_S)

	if (!is_stack)									# 'Horizontal stack'
		col = (is_hbar) ? 2 : 1						# Horizontal and Vertical bars get shits in different columns
		n_groups = size(_argD[1].data,1)
		n_in_each_group = fill(0, n_groups)			# Vec with n_in_group elements
		for k = 1:n_groups n_in_each_group[k] = sum(.!isnan.(_arg[k,:][2:end]))  end
		if (sum(n_in_each_group) == n_in_group * n_groups)
			g_shifts_ = linspace((-bw + new_bw)/2, (bw - new_bw)/2, n_in_group)
			for k = 1:n_in_group					# Loop over number of bars in a group
				for r = 1:n_groups  _argD[k].data[r, col] += g_shifts_[k]  end
			end
		else
			ic::Int   = ceil(Int, (size(_arg,2)-1)/2)		# index of the center bar (left from middle if even)
			g_shifts0 = linspace((-bw + new_bw)/2, (bw - new_bw)/2, n_in_group)
			for m = 1:n_groups						# Loop over number of groups
				if (n_in_each_group[m] == n_in_group)	# This group is simple. It has all the bars
					for k = 1:n_in_group  _argD[k].data[m, col] += g_shifts0[k]  end	# Loop over all the bars in group
					continue
				end

				g_shifts = collect(g_shifts0)
				x     = isnan.(_arg[m,:][2:end])
				n_low = sum(.!x[1:ic]);		n_high = sum(.!x[ic+1:end])
				clow  = !all(x[1:ic-1]);	chigh = !all(x[ic+1:end])	# See if both halves want the center pos
				dx = (clow && chigh) ? new_bw/2 : 0.0
				for n = 1:ic					# Lower half
					g_shifts[n] += ((ic-n)-sum(.!x[n+1:ic])) * new_bw - dx
				end
				for n = ic+1:n_in_group			# Upper half
					g_shifts[n] -= ((n-ic)-sum(.!x[ic:n-1])+!x[ic]) * new_bw - dx
				end

				# Compensate when bar distribution is not symetric about the center
				if     (n_high == 0 && n_in_each_group[m] > 1)  g_shifts .+= (n_low-1) * new_bw/2
				elseif (n_low == 0 && n_in_each_group[m] > 1)   g_shifts .-= (n_high-1) * new_bw/2
				elseif (n_in_each_group[m] > 1)                 g_shifts .-= (n_high - n_low) * new_bw/2
				end
				(iseven(n_in_group)) && (g_shifts .+= new_bw/2)		# Don't get it why I have to do this

				for k = 1:n_in_group  _argD[k].data[m, col] += g_shifts[k]  end		# Loop over all the bars in this group
			end
		end
	end

	if (!got_usr_R)									# Need to recompute -R
		info::GMTdataset = gmt("gmtinfo -C", _argD)
		data::Matrix{<:Float64} = info.data
		(data[3] > 0.0) && (data[3] = 0.0)	# If not negative then must be 0
		if (!is_hbar)
			dx::Float64 = (data[2] - data[1]) * 0.005 + new_bw/2;
			dy::Float64 = (data[4] - data[3]) * 0.005;
			data[1] -= dx;	data[2] += dx;	data[4] += dy;
			(data[3] != 0) && (data[3] -= dy);
		else
			dx = (data[2] - data[1]) * 0.005
			dy = (data[4] - data[3]) * 0.005 + new_bw/2;
			data[1] = 0.0;	data[2] += dx;	data[3] -= dy;	data[4] += dy;
			(data[1] != 0) && (data[1] -= dx);
		end
		data = round_wesn(data)		# Add a pad if not tight
		new_opt_R = @sprintf(" -R%.15g/%.15g/%.15g/%.15g", data[1], data[2], data[3], data[4])
		cmd = replace(cmd, opt_R => new_opt_R)
		(is_waterfall) && (cmd2 *= CTRL.pocket_J[1] * new_opt_R)
	end
	(is_waterfall && got_usr_R) && (cmd2 *= CTRL.pocket_J[1] * CTRL.pocket_R[1])
	return cmd, _argD, cmd2
end

# ---------------------------------------------------------------------------------------------------
function recompute_R_4bars!(cmd::String, opt_R::String, arg1)
	# Recompute the -R for bar plots (non-grouped), taking into account the width embeded in option S
	opt_S = scan_opt(cmd, "-S")
	sub_b = ((ind = findfirst("+", opt_S)) !== nothing) ? opt_S[ind[1]:end] : ""	# The +Base modifier
	(sub_b != "") && (opt_S = opt_S[1:ind[1]-1])# Strip it because we need to (re)find Bar width
	bw = (isletter(opt_S[end])) ? parse(Float64, opt_S[3:end-1]) : parse(Float64, opt_S[2:end])	# Bar width
	info = gmt("gmtinfo -C", arg1)
	dx::Float64 = (info.data[2] - info.data[1]) * 0.005 + bw/2;
	dy::Float64 = (info.data[4] - info.data[3]) * 0.005;
	info.data[1] -= dx;	info.data[2] += dx;	info.data[4] += dy;
	info.data = round_wesn(info.data)		# Add a pad if not-tight
	new_opt_R = @sprintf(" -R%.15g/%.15g/%.15g/%.15g", info.data[1], info.data[2], 0, info.data[4])
	cmd = replace(cmd, opt_R => new_opt_R)
end

# ---------------------------------------------------------------------------------------------------
function make_color_column(d::Dict, cmd::String, opt_i::String, len::Int, N_args::Int, n_prev::Int, is3D::Bool, got_Ebars::Bool, bar_ok::Bool, bar_fill, arg1, arg2)
	# See if we got a CPT. If yes, there is quite some work to do if no color column provided in input data.
	# N_ARGS will be == n_prev+1 when a -Ccpt was used. Otherwise they are equal.

	mz, the_kw = find_in_dict(d, [:zcolor :markerz :mz])
	if ((!(N_args > n_prev || len < length(cmd)) && mz === nothing) && !bar_ok)		# No color request, so return right away
		return cmd, arg1, arg2, N_args, false
	end

	# Filled polygons with -Z don't need extra col
	((val = find_in_dict(d, [:G :fill], false)[1]) == "+z") && return cmd, arg1, nothing, N_args, false

	if     (isa(arg1, Vector{<:GMTdataset}))           n_rows, n_col = size(arg1[1])
	elseif (isa(arg1,GMTdataset) || isa(arg1, Array))  n_rows, n_col = size(arg1)
	end

	(isa(mz, Bool) && mz) && (mz = 1:n_rows)

	if ((mz !== nothing && length(mz) != n_rows) || (mz === nothing && opt_i != ""))
		warn1 = string("Probably color column in '", the_kw, "' has incorrect dims. Ignoring it.")
		warn2 = "Plotting with color table requires adding one more column to the dataset but your -i
		option didn't do it, so you won't get what you expect. Try -i0-1,1 for 2D or -i0-2,2 for 3D plots"
		(mz !== nothing) ? @warn(warn1) : @warn(warn2)
		return cmd, arg1, arg2, N_args, true
	end

	if (!isempty(bar_fill))
		if (isa(arg1,GMTdataset) || isa(arg1, Array))  arg1         = hcat(arg1, 1:n_rows)
		elseif (isa(arg1, Vector{<:GMTdataset}))       arg1[1].data = hcat(arg1[1].data, 1:n_rows)
		end
		arg2::GMTcpt = gmt(string("makecpt -T1/$(n_rows+1)/1 -C" * join(bar_fill, ",")))
		current_cpt[1] = arg2
		(!occursin(" -C", cmd)) && (cmd *= " -C")	# Need to inform that there is a cpt to use
		find_in_dict(d, [:G :fill])					# Must delete the :fill. Not used anymore
		return cmd, arg1, arg2, 2, true
	end

	if (n_col <= 2+is3D)
		if (mz !== nothing)
			if (isa(arg1,GMTdataset) || isa(arg1, Array))  arg1    = hcat(arg1, mz[:])
			elseif (isa(arg1, Vector{<:GMTdataset}))       arg1[1] = hcat(arg1[1], mz[:]) 
			end
		else
			cmd *= " -i0-$(1+is3D),$(1+is3D)"
			if ((val = find_in_dict(d, [:markersize :ms :size], false)[1]) !== nothing && isa(val, Vector))
				cmd *= "-$(2+is3D)"		# Because we know that an extra col will be added later
			end
		end
	else
		if (mz !== nothing)				# Here we must insert the color col right after the coords
			if (isa(arg1,GMTdataset) || isa(arg1, Array))  arg1    = hcat(arg1[:,1:2+is3D],    mz[:], arg1[:,3+is3D:end])
			elseif (isa(arg1, Vector{<:GMTdataset}))       arg1[1] = hcat(arg1[1][:,1:2+is3D], mz[:], arg1[1][:,3+is3D:end])
			end
		elseif (got_Ebars)				# The Error bars case is very multi. Don't try to guess then.
			cmd *= " -i0-$(1+is3D),$(1+is3D),$(2+is3D)-$(n_col-1)"
		end
	end

	if (N_args == n_prev)				# No cpt transmitted, so need to compute one
		if (mz !== nothing)                                    mi, ma = extrema(mz)
		else
			the_col = min(n_col,3)+is3D
			got_Ebars && (the_col -= 1)			# Bars => 2 cols
			if     (isa(arg1, Vector{<:GMTdataset}))           mi, ma = extrema(view(arg1[1], :, the_col))
			elseif (isa(arg1,GMTdataset) || isa(arg1, Array))  mi, ma = extrema(view(arg1,    :, the_col))
			end
		end
		just_C = cmd[len+2:end];	reset_i = ""
		if ((ind = findfirst(" -i", just_C)) !== nothing)
			reset_i = just_C[ind[1]:end]
			just_C  = just_C[1:ind[1]-1]
		end
		arg2 = gmt(string("makecpt -T", mi-0.001*abs(mi), '/', ma+0.001*abs(ma), " ", just_C) * (IamModern[1] ? " -H" : ""))
		current_cpt[1] = arg2
		if (occursin(" -C", cmd))  cmd = cmd[1:len+3]  end		# Strip the cpt name
		if (reset_i != "")  cmd *= reset_i  end		# Reset -i, in case it existed

		(!occursin(" -C", cmd)) && (cmd *= " -C")	# Need to inform that there is a cpt to use
		N_args = 2
	end

	return cmd, arg1, arg2, N_args, true
end

# ---------------------------------------------------------------------------------------------------
function get_marker_name(d::Dict, arg1, symbs::Vector{Symbol}, is3D::Bool, del::Bool=true)
	marca::String = "";		N = 0
	for symb in symbs
		if (haskey(d, symb))
			t = d[symb]
			if (isa(t, Tuple))				# e.g. marker=(:r, [2 3])
				msg = "";	cst = false
				o::String = string(t[1])
				if     (startswith(o, "E"))  opt = "E";  N = 3; cst = true
				elseif (startswith(o, "e"))  opt = "e";  N = 3
				elseif (o == "J" || startswith(o, "Rot"))  opt = "J";  N = 3; cst = true
				elseif (o == "j" || startswith(o, "rot"))  opt = "j";  N = 3
				elseif (o == "M" || startswith(o, "Mat"))  opt = "M";  N = 3
				elseif (o == "m" || startswith(o, "mat"))  opt = "m";  N = 3
				elseif (o == "R" || startswith(o, "Rec"))  opt = "R";  N = 3
				elseif (o == "r" || startswith(o, "rec"))  opt = "r";  N = 2
				elseif (o == "V" || startswith(o, "Vec"))  opt = "V";  N = 2
				elseif (o == "v" || startswith(o, "vec"))  opt = "v";  N = 2
				elseif (o == "w" || o == "pie" || o == "web" || o == "wedge")  opt = "w";  N = 2
				elseif (o == "W" || o == "Pie" || o == "Web" || o == "Wedge")  opt = "W";  N = 2
				end
				if (N > 0)  marca, arg1, msg = helper_markers(opt, t[2], arg1, N, cst)  end
				(msg != "") && error(msg)
				if (length(t) == 3 && isa(t[3], NamedTuple))
					if (marca == "w" || marca == "W")	# Ex (spiderweb): marker=(:pie, [...], (inner=1,))
						marca *= add_opt(t[3], (inner="/", arc="+a", radial="+r", size=("", arg2str, 1), pen=("+p", add_opt_pen)) )
					elseif (marca == "m" || marca == "M")
						marca *= vector_attrib(t[3])
					end
				end
			elseif (isa(t, NamedTuple))		# e.g. marker=(pie=true, inner=1, ...)
				key = keys(t)[1];	opt = ""
				if     (key == :w || key == :pie || key == :web || key == :wedge)  opt = "w"
				elseif (key == :W || key == :Pie || key == :Web || key == :Wedge)  opt = "W"
				elseif (key == :b || key == :bar)     opt = "b"
				elseif (key == :B || key == :HBar)    opt = "B"
				elseif (key == :l || key == :letter)  opt = "l"
				elseif (key == :K || key == :Custom)  opt = "K"
				elseif (key == :k || key == :custom)  opt = "k"
				elseif (key == :M || key == :Matang)  opt = "M"
				elseif (key == :m || key == :matang)  opt = "m"
				end
				if (opt == "w" || opt == "W")
					marca = opt * add_opt(t, (size=("", arg2str, 1), inner="/", arc="+a", radial="+r", pen=("+p", add_opt_pen)))
				elseif (opt == "b" || opt == "B")
					marca = opt * add_opt(t, (size=("", arg2str, 1), base="+b", Base="+B"))
				elseif (opt == "l")
					marca = opt * add_opt(t, (size=("", arg2str, 1), letter="+t", justify="+j", font=("+f", font)))
				elseif (opt == "m" || opt == "M")
					marca = opt * add_opt(t, (size=("", arg2str, 1), arrow=("", vector_attrib)))
				elseif (opt == "k" || opt == "K")
					marca = opt * add_opt(t, (custom="", size="/"))
				end
			else
				t1::String = string(t)
				(t1[1] != 'T') && (t1 = lowercase(t1))
				if     (t1 == "-" || t1 == "x-dash")    marca = "-"
				elseif (t1 == "+" || t1 == "plus")      marca = "+"
				elseif (t1 == "a" || t1 == "*" || t1 == "star")  marca = "a"
				elseif (t1 == "k" || t1 == "custom")    marca = "k"
				elseif (t1 == "x" || t1 == "cross")     marca = "x"
				elseif (is3D && (t1 == "u" || t1 == "cube"))  marca = "u"	# Must come before next line
				elseif (t1[1] == 'c')                   marca = "c"
				elseif (t1[1] == 'd')                   marca = "d"		# diamond
				elseif (t1 == "g" || t1 == "octagon")   marca = "g"
				elseif (t1[1] == 'h')                   marca = "h"		# hexagon
				elseif (t1 == "i" || t1 == "inverted_tri")  marca = "i"
				elseif (t1[1] == 'l')                   marca = "l"		# letter
				elseif (t1 == "n" || t1 == "pentagon")  marca = "n"
				elseif (t1 == "p" || t1 == "." || t1 == "point")  marca = "p"
				elseif (t1[1] == 's')                   marca = "s"		# square
				elseif (t1[1] == 't' || t1 == "^")      marca = "t"		# triangle
				elseif (t1[1] == 'T')                   marca = "T"		# Triangle
				elseif (t1[1] == 'y')                   marca = "y"		# y-dash
				elseif (t1[1] == 'f')                   marca = "f"		# for Faults in legend
				elseif (t1[1] == 'q')                   marca = "q"		# for Quoted in legend
				end
				t1 = string(t)		# Repeat conversion for the case it was lower-cased above
				# Still need to check the simpler forms of these
				if (marca == "")  marca = helper2_markers(t1, ["e", "ellipse"])   end
				if (marca == "")  marca = helper2_markers(t1, ["E", "Ellipse"])   end
				if (marca == "")  marca = helper2_markers(t1, ["j", "rotrect"])   end
				if (marca == "")  marca = helper2_markers(t1, ["J", "RotRect"])   end
				if (marca == "")  marca = helper2_markers(t1, ["m", "matangle"])  end
				if (marca == "")  marca = helper2_markers(t1, ["M", "Matangle"])  end
				if (marca == "")  marca = helper2_markers(t1, ["r", "rectangle"])   end
				if (marca == "")  marca = helper2_markers(t1, ["R", "RRectangle"])  end
				if (marca == "")  marca = helper2_markers(t1, ["v", "vector"])  end
				if (marca == "")  marca = helper2_markers(t1, ["V", "Vector"])  end
				if (marca == "")  marca = helper2_markers(t1, ["w", "pie", "web"])  end
				if (marca == "")  marca = helper2_markers(t1, ["W", "Pie", "Web"])  end
			end
			(del) && delete!(d, symb)
			break
		end
	end
	return marca, arg1, N > 0
end

function helper_markers(opt::String, ext, arg1, N::Int, cst::Bool)
	# Helper function to deal with the cases where one sends marker's extra columns via command
	# Example that will land and be processed here:  marker=(:Ellipse, [30 10 15])
	# N is the number of extra columns
	marca = "";	 msg = ""
	if (size(ext,2) == N && arg1 !== nothing)	# Here ARG1 is supposed to be a matrix that will be extended.
		S = Symbol(opt)
		marca, arg1 = add_opt(add_opt, (Dict(S => (par=ext,)), opt, "", [S]), (par="|",), true, arg1)
	elseif (cst && length(ext) == 1)
		marca = opt * "-" * string(ext)
	else
		msg = string("Wrong number of extra columns for marker (", opt, "). Got ", size(ext,2), " but expected ", N)
	end
	return marca, arg1, msg
end

function helper2_markers(opt::String, alias::Vector{String})::String
	marca = ""
	if (opt == alias[1])			# User used only the one letter syntax
		marca = alias[1]
	else
		for k = 2:length(alias)		# Loop because of cases like ["w" "pie" "web"]
			o2 = alias[k][1:min(2,length(alias[k]))]	# check the first 2 chars and Ro, Rotrect or RotRec are all good
			if (startswith(opt, o2))  marca = alias[1]; break  end		# Good when, for example, marker=:Pie
		end
	end

	# If we still have found nothing, assume that OPT is a full GMT opt string (e.g. W/5+a30+r45+p2,red)
	(marca == "" && opt[1] == alias[1][1]) && (marca = opt)
	return marca
end

# ---------------------------------------------------------------------------------------------------
function seek_custom_symb(marca::String, with_k::Bool=false)::Tuple{String, String}
	# If 'marca' is a custom symbol, seek it first in GMT.jl share/custom dir.
	# Always return the marker name (modified or not) plus the marker symbol name with extension
	# (but not its path) in the case the marker name was found in GMT.jl share/custom dir.
	# The WITH_K arg is to allow calling this fun with a sym name already prefaced with 'k', or not
	(with_k && marca[1] != 'k') && return marca, ""		# Not a custom symbol, return what we got.

	cus_path = joinpath(dirname(pathof(GMT))[1:end-4], "share", "custom")
	cus = readdir(cus_path)						# Get the list of all custom symbols in this dir.
	s = split(marca, '/')
	ind_s = with_k ? 2 : 1
	r = cus[contains.(cus, s[1][ind_s:end])]	# If found, returns the symbol name including the extension.
	if (!isempty(r))							# Means the requested symbol was found in GMT.jl share/custom
		_mark = splitext(r[1])[1]				# Get the marker name but without extension
		_siz  = split(marca, '/')[2]			# The custom symbol size
		_marca = (with_k ? "k" : "")  * joinpath(cus_path, _mark) * "/" * _siz
		(GMTver <= v"6.4" && (length(_marca) - length(_siz) -2) > 62) && warn("Due to a GMT <= 6.4 limitation the length of full (name+path) custom symbol name cannot be longer than 62 bytes.")
		return _marca, r[1]
	end
	return marca, ""							# A custom symbol from the official GMT collection.
end

# ---------------------------------------------------------------------------------------------------
function check_caller(d::Dict, cmd::String, opt_S::String, opt_W::String, caller::String, g_bar_fill::Array{String}, O::Bool)::String
	# Set sensible defaults for the sub-modules "scatter" & "bar"
	if (caller == "scatter")
		if (opt_S == "")  cmd *= " -Sc5p"  end
	elseif (caller == "scatter3")
		if (opt_S == "")  cmd *= " -Su2p"  end
	elseif (caller == "lines")
		if (!occursin("+p", cmd) && opt_W == "") cmd *= " -W0.5p"  end # Do not leave without a pen specification
	elseif (caller == "bar")
		if (opt_S == "")
			bar_type = 0
			if (haskey(d, :bar))
				cmd, bar_opts = parse_bar_cmd(d, :bar, cmd, "Sb")
				bar_type = 1;	delete!(d, :bar)
			elseif (haskey(d, :hbar))
				cmd, bar_opts = parse_bar_cmd(d, :hbar, cmd, "SB")
				bar_type = 2;	delete!(d, :hbar)
			end
			if (bar_type == 0 || bar_opts == "")	# bar_opts == "" means only bar=true or hbar=true was used
				gap::Float64 = ((val = find_in_dict(d, [:bargap])[1]) === nothing) ? 0.8 : (val > 1 ? (1.0 - val/100) : (1-val))		# Gap between bars in a group
				opt = (haskey(d, :width)) ? add_opt(d, "", "",  [:width]) : "$gap"	# 0.8 is the default
				_Stype = (bar_type == 2) ? " -SB" : " -Sb"
				cmd *= _Stype * opt * "u"

				optB = (haskey(d, :base)) ? add_opt(d, "", "",  [:base]) : "0"
				cmd *= "+b" * optB
			end
		end
		(isempty(g_bar_fill) && !occursin(" -G", cmd) && !occursin(" -C", cmd)) && (cmd *= " -G0/115/190")	# Default color
	elseif (caller == "bar3")
		if (haskey(d, :noshade) && occursin("-So", cmd))
			cmd = replace(cmd, "-So" => "-SO", count=1);
			delete!(d, :noshade)
		end
		if (!occursin(" -G", cmd) && !occursin(" -C", cmd))  cmd *= " -G0/115/190"	end
		if (!occursin(" -J", cmd))  cmd *= " -JX12c/0"  end
	end

	if (occursin('3', caller))
		if (!occursin(" -B", cmd) && !O)  cmd *= def_fig_axes3[1]  end	# For overlays default is no axes
	end

	return cmd
end

# ---------------------------------------------------------------------------------------------------
function parse_bar_cmd(d::Dict, key::Symbol, cmd::String, optS::String, no_u::Bool=false)::Tuple{String, String}
	# Deal with parsing the 'bar' & 'hbar' keywors of psxy. Also called by plot/bar3. For this
	# later module if input is not a string or NamedTuple the scatter options must be processed in bar3().
	# KEY is either :bar or :hbar
	# OPTS is either "Sb", "SB" or "So"
	# NO_U if true means to NOT automatic adding of flag 'u'
	opt::String = "";	got_str = false
	if (haskey(d, key))
		if (isa(d[key], String))
			opt, got_str = d[key], true
			cmd *= " -" * optS * opt;	delete!(d, key)
		elseif (isa(d[key], NamedTuple))
			opt = add_opt(d, "", optS, [key], (width="",unit="1",base="+b",height="+B",nbands="+z",Nbands="+Z"))
		elseif (isa(d[key], Bool) && d[key])
		else
			error("Argument of the *bar* keyword can be only a string or a NamedTuple.")
		end
	end

	if (opt != "" && !got_str)				# Still need to finish parsing this
		flag_u = no_u ? "" : 'u'
		if ((ind = findfirst("+", opt)) !== nothing)	# See if need to insert a 'u'
			if (!isletter(opt[ind[1]-1]))  opt = opt[1:ind[1]-1] * flag_u * opt[ind[1]:end]  end
		else
			pb = (optS != "So") ? "+b0" : ""		# The default for bar3 (So) is set in the bar3() fun
			if (!isletter(opt[end]))  opt *= flag_u	  end	# No base set so default to ...
			opt *= pb
		end
		cmd *= opt
	end
	return cmd, opt
end
