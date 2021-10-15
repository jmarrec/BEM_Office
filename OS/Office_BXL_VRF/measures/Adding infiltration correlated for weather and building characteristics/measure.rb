# see the URL below for information on how to write OpenStudio measures
# http://nrel.github.io/OpenStudio-user-documentation/measures/measure_writing_guide/

# start the measure
class Infiltration < OpenStudio::Ruleset::ModelUserScript

  # human readable name
  def name
    return "Adding infiltration correlated for weather and building characteristics"
  end

  # human readable description
  def description
    return "This measure incorporates infiltration that varies with weather and HVAC operation, and takes into account building geometry (height, above-ground exterior surface area, and volume). It is based on work published by Ng et al. (2015) <a href='http://dx.doi.org/10.1016/j.enbuild.2014.11.078'>'Improving infiltration modeling in commercial building energy models'</a>. This method of calculating infiltration was developed using seven of the DOE commercial reference building models (<a href='http://energy.gov/eere/buildings/commercial-reference-buildings'>DOE 2011</a>) and Chicago TMY2 weather. Ng et al. (2015) shows that utilizing this method improves the agreement between infiltration calculated using energy simulation and airflow modeling software. This method also improves accuracy when compared with existing approaches to estimating infiltration in commercial building energy calculations (i.e., no or constant infiltration, or using correlations based on research of residential buildings). Updates to the measure are planned for the future, including but not limited to selecting building type/size and climate zone. Please send an email to infiltration-request@nist.gov (Subject: SUBSCRIBE) or lisa.ng@nist.gov to receive updates by email or for questions/feedback on the measure."
  end

  # human readable description of modeling approach
  def modeler_description
    return "This measure will remove any existing infiltration objects (OS:SpaceInfiltration:DesignFlowRate and OS:SpaceInfiltration:EffectiveLeakageArea) when generating the model. Every zone will then get two OS:SpaceInfiltration:DesignFlowRate objects that add infiltration using the 'Flow per Exterior Surface Area' input option, one infiltration object when the HVAC system is on and one object when the HVAC system is off. This is because the measure is based on work by Ng et al. (2015) <a href='http://dx.doi.org/10.1016/j.enbuild.2014.11.078'>'Improving infiltration modeling in commercial building energy models'</a>, which provides a set of correlations when the system was on and when the system was off. The method assumes that HVAC operation is set by schedule, though it may not reflect actual simulation/operation when fan operation may depend on internal loads and temperature setpoints. By default, interior zones will receive no infiltration. The infiltration per area of exterior envelope (i.e., building envelope airtightness) must be entered by the user (Idesign (m^3/s/m^2 @ 4 Pa)). The measure assumes that infiltration is evenly distributed across the entire building envelope, including the roof. The user must select the desired schedule that corresponds with typical operation of the HVAC system from the drop-down menu of Schedule Rule Sets that already exist within the baseline model. The measure will make two copies of this Schedule Rule Set and rename them 'HVAC On Infiltration' and 'HVAC Off Infiltration'. Thus, the 'HVAC On Infiltration' has values of 1 when it is 1 in the selected HVAC Schedule and 0 when it is 0 in the selected HVAC Schedule. In contrast, the 'HVAC Off Infiltration' will be modified to have the opposite schedule, i.e.,  values of 0 when it is 1 in the selected HVAC Schedule and 1 when it is 0 in the selected HVAC Schedule. Equations are provided by <a href='http://dx.doi.org/10.1016/j.enbuild.2014.11.078'> Ng et al. (2015) </a> to calculate the coefficients required by the OS:SpaceInfiltration:DesignFlowRate object (A, B, C, and D) using building height, above-ground exterior surface area, volume, and net system flow normalized by exterior surface area. Instead of the user doing this, the measure will utilize the information in the baseline model to calculate height, above-ground exterior surface area, and volume. The user must enter the design building 'Total supply to zones' rate, an appropriate building total return rate ('Total return from zones'), and the sum of any exhaust fans in the model ('Total of exhaust fans') in m^3/s.  The measure will then calculate the net system flow normalized by exterior surface area in order to complete the inputs for the OS:SpaceInfiltration:DesignFlowRate object."
  end

  # define the arguments that the user will input
  def arguments(model)
    args = OpenStudio::Ruleset::OSArgumentVector.new
    
    #pick a schedule
    #sched_names = OpenStudio::Ruleset::makeChoiceArgumentOfWorkspaceObjects("HVAC Schedule Name","OS_Schedule_Ruleset".to_IddObjectType,model,true)

    all_scheds = model.getSchedules
    sched_name_vec = OpenStudio::StringVector.new
    all_scheds.each do |sched|
      sched_name_vec << sched.name.get
    end
    sched_names = OpenStudio::Ruleset::OSArgument::makeChoiceArgument('HVAC Schedule Name', sched_name_vec, true)
    args << sched_names

    #enter I design value
    idvalue = OpenStudio::Ruleset::OSArgument::makeDoubleArgument('idesign', false)
    idvalue.setDefaultValue(0.0)
    idvalue.setDisplayName("Idesign (m^3/s/m^2 @ 4 Pa)")
    args << idvalue

    #enter supply_flow value
    supply_flow = OpenStudio::Ruleset::OSArgument::makeDoubleArgument('Supply Flow', false)
    supply_flow.setDefaultValue(0.0)
    supply_flow.setDisplayName("Total supply to zones (m^3/s)")
    args << supply_flow
    
    #enter return value
    return_flow = OpenStudio::Ruleset::OSArgument::makeDoubleArgument('Return Flow', false)
    return_flow.setDefaultValue(0.0)
    return_flow.setDisplayName("Total return from zones (m^3/s)")
    args << return_flow
    
    #enter exhaust value
    exhaust_flow = OpenStudio::Ruleset::OSArgument::makeDoubleArgument('Exhaust Flow', false)
    exhaust_flow.setDefaultValue(0.0)
    exhaust_flow.setDisplayName("Total of exhaust fans (m^3/s)")
    args << exhaust_flow
    
    return args
  end

  # define what happens when the measure is run
  def run(model, runner, user_arguments)
    super(model, runner, user_arguments)

    # use the built-in error checking
    if !runner.validateUserArguments(arguments(model), user_arguments)
      return false
    end

    # assign the user inputs to variables
    #get user selected schedule
    s_name = runner.getStringArgumentValue('HVAC Schedule Name',user_arguments)
    runner.registerInfo("s_name: #{s_name}")
    #get user input i design 
    ides = runner.getDoubleArgumentValue('idesign',user_arguments)
    runner.registerInfo("I Design: #{ides}")
    #get user input supply design 
    supply_flow = runner.getDoubleArgumentValue('Supply Flow',user_arguments)
    runner.registerInfo("Supply to zones: #{supply_flow}")
    #get user input return design 
    return_flow = runner.getDoubleArgumentValue('Return Flow',user_arguments)
    runner.registerInfo("Return from zones: #{return_flow}")
    #get user input exhaust design 
    exhaust_flow = runner.getDoubleArgumentValue('Exhaust Flow',user_arguments)
    runner.registerInfo("Exhaust fans: #{exhaust_flow}")
    
    if supply_flow <= 0
      runner.registerError("The supply to zones has to be greater than zero.")
      return false
    end
    if return_flow <= 0
      runner.registerError("The return to zones has to be greater than zero.")
      return false
    end
    #if exhaust_flow <= 0
    #  runner.registerError("The exhaust flow has to be greater than zero.")
    #  return false
    #end

    selected_sched = nil
    on_schedule = nil
    off_schedule = nil
    #find existing schedules if there are any
    ruleSchedules = model.getScheduleRulesets
    ruleSchedules.each do |sched|
      if sched.name.get == "Infiltration HVAC On Schedule"
        sched.remove
        runner.registerInfo("Removed existing infiltration on schedule")
      end
      if sched.name.get == "Infiltration HVAC Off Schedule"
        sched.remove
        runner.registerInfo("Removed existing infiltration off schedule")
      end
    end
    #check if the selected schedule is a ruleset schedule
    ruleSchedules = model.getScheduleRulesets
    #define these two variables
    ruleSchedules.each do |sched|
      if sched.name.get == s_name
        #clone this schedule for On schedule
        on_schedule = sched.clone.to_ScheduleRuleset.get
        on_schedule.setName("Infiltration HVAC On Schedule");
        #create off schedule
        off_schedule = OpenStudio::Model::ScheduleRuleset.new(model, 1)
        off_schedule.setName("Infiltration HVAC Off Schedule");

        rules = sched.scheduleRules
        rules.each do |rule|
          oldDaySched = rule.daySchedule
          newDaySched = OpenStudio::Model::ScheduleDay.new(model)
          index = 0
          for index in 0..oldDaySched.times.size-1
            oldValue = oldDaySched.values[index]
            if oldValue == 0
              newValue = 1
            else
              newValue = 0
            end
            newDaySched.addValue(oldDaySched.times[index], newValue)
          end
          newrule = OpenStudio::Model::ScheduleRule.new(off_schedule, newDaySched)
          newrule.setApplySunday(rule.applySunday)
          newrule.setApplyMonday(rule.applyMonday)
          newrule.setApplyTuesday(rule.applyTuesday)
          newrule.setApplyWednesday(rule.applyWednesday)
          newrule.setApplyThursday(rule.applyThursday)
          newrule.setApplyFriday(rule.applyFriday)
          newrule.setApplySaturday(rule.applySaturday)
        end

        runner.registerInfo("Created new schedules")
        #selected_sched = sched
        #runner.registerInfo("Found Ruleset Schedule: #{selected_sched.name.get}")
        break
      end
    end
    
    #support other schedules when editable in OS
    #check if the selected schedule is a compact schedule
    compactSchedules = model.getScheduleCompacts
    compactSchedules.each do |sched|
      if sched.name.get == s_name
        #selected_sched = sched
        #runner.registerInfo("Found Compact Schedule: #{selected_sched.name.get}")
        runner.registerError("The schedule selected is a compact schedule.  It must be a ruleset schedule.")
        return false
      end
    end

    #check if the selected schedule is a constant schedule
    constSchedules = model.getScheduleConstants
    constSchedules.each do |sched|
      if sched.name.get == s_name
        #selected_sched = sched
        #runner.registerInfo("Found Constant Schedule: #{selected_sched.name.get}")
        runner.registerError("The schedule selected is a constant schedule.  It must be a ruleset schedule.")
        return false
      end
    end

    #check if the selected schedule is a fixed interval schedule
    fixedSchedules = model.getScheduleFixedIntervals
    fixedSchedules.each do |sched|
      if sched.name.get == s_name
        #selected_sched = sched
        #runner.registerInfo("Found Fixed Interval Schedule: #{selected_sched.name.get}")
        runner.registerError("The schedule selected is a fixed interval schedule.  It must be a ruleset schedule.")
        return false
      end
    end
    #check if the selected schedule is a variable interval schedule
    variableSchedules = model.getScheduleVariableIntervals
    variableSchedules.each do |sched|
      if sched.name.get == s_name
        #selected_sched = sched
        #runner.registerInfo("Found Variable Interval Schedule: #{selected_sched.name.get}")
        runner.registerError("The schedule selected is a variable interval schedule.  It must be a ruleset schedule.")
        return false
      end
    end

    # check the volume for reasonableness
    building = model.getBuilding
    building_volume = building.airVolume
    if building_volume <= 0
      runner.registerError("The building volume must be a positive value.")
      return false
    end
    runner.registerInfo("Building volume: #{building_volume}.")

    #get area of surfaces with outdoor boundary condition. Take zone multipliers into account
    surfaces = model.getSurfaces
    exterior_surface_gross_area = 0
    space_warning_issued = []
    maxZ = 0.0 
    
    surfaces.each do |s|
    
      # find the maximum z value of all surfaces for the building height
      #z is relative to the zone's origin so add zOrigin
      if not s.space.empty?
        s.vertices.each do |vert|
          if vert.z + s.space.get.zOrigin > maxZ
            maxZ = vert.z + s.space.get.zOrigin
          end
        end 
      end

      next if not s.outsideBoundaryCondition == "Outdoors"

      #get surface area adjusting for zone multiplier
      space = s.space
      if not space.empty?
        zone = space.get.thermalZone
      end
      if not zone.empty?
        zone_multiplier = zone.get.multiplier
        if zone_multiplier > 1 and not space_warning_issued.include?(space.get.name.to_s)
          runner.registerInfo("Space #{space.get.name.to_s} in thermal zone #{zone.get.name.to_s} has a zone multiplier of #{zone_multiplier}. Adjusting area calculations.")
          space_warning_issued << space.get.name.to_s
        end
      else
        zone_multiplier = 1 #space is not in a thermal zone
        runner.registerWarning("Space #{space.get.name.to_s} is not in a thermal zone and won't be included in in the simulation. For area calculations in this measure a zone multiplier of 1 will be assumed.")
      end
      exterior_surface_gross_area = exterior_surface_gross_area + s.grossArea * zone_multiplier

    end #end of surfaces.each do
    runner.registerInfo("Exterior surface area: #{exterior_surface_gross_area}")
    runner.registerInfo("Building height: #{maxZ}")

    #compute infiltration coefficients
    ma_on = 0.0001 
    mb_on = 0.0002 
    md_on = 0.0008 
    na_on = 0.0933 
    nb_on = 0.0245
    nd_on = 0.1312 
    pa_on = -47 
    pb_on = -5 
    pd_on = -28 
    mb_off = 0.0002
    md_off = -0.00002
    nb_off = 0.0430
    nd_off = 0.211

    fn = (supply_flow - return_flow - exhaust_flow) / exterior_surface_gross_area
    runner.registerInfo("Computed fn: #{fn}")

    sV = exterior_surface_gross_area / building_volume
    runner.registerInfo("Computed sV: #{sV}")

    aon = ma_on * maxZ + na_on * sV + pa_on * fn
    bon = mb_on * maxZ + nb_on * sV + pb_on * fn
    don = md_on * maxZ + nd_on * sV + pd_on * fn

    boff = mb_off * maxZ + nb_off * sV
    doff = md_off * maxZ + nd_off * sV
    runner.registerInfo("Computed aon: #{aon}")
    runner.registerInfo("Computed bon: #{bon}")
    runner.registerInfo("Computed don: #{don}")
    runner.registerInfo("Computed boff: #{boff}")
    runner.registerInfo("Computed doff: #{doff}")

    #get ELA space infiltration objects used in the model
    ela_infil_objects = model.getSpaceInfiltrationEffectiveLeakageAreas
    #reporting initial condition of model
    if ela_infil_objects.size > 0
      runner.registerInfo("The initial model contained #{ela_infil_objects.size} ELA space infiltration objects.")
    else
      runner.registerInfo("The initial model did not contain any ELA space infiltration objects.")
    end
    
    #remove ELA space infiltration objects
    number_removed = 0
    number_left = 0
    ela_infil_objects.each do |ela_infil_object|
      opt_space_type = ela_infil_object.spaceType
      if opt_space_type.empty?
        ela_infil_object.remove
        number_removed = number_removed +1
      elsif opt_space_type.get.spaces.size > 0
        ela_infil_object.remove
        number_removed = number_removed +1
      else
        number_left = number_left +1
      end
    end
    if number_removed > 0
      runner.registerInfo("#{number_removed} ELA infiltration objects were removed.")
    end
    if number_left > 0
      runner.registerInfo("#{number_left} ELA infiltration objects in unused space types were left in the model. They will not be altered.")
    end    
    
    #get design flow rate space infiltration objects used in the model
    space_infiltration_objects = model.getSpaceInfiltrationDesignFlowRates
    
    #reporting initial condition of model
    if space_infiltration_objects.size > 0
      runner.registerInfo("The initial model contained #{space_infiltration_objects.size} design flow rate space infiltration objects.")
    else
      runner.registerInfo("The initial model did not contain any design flow rate space infiltration objects.")
    end
    
    #remove design flow rate space infiltration objects
    number_removed = 0
    number_left = 0
    space_infiltration_objects.each do |space_infiltration_object|
      opt_space_type = space_infiltration_object.spaceType
      if opt_space_type.empty?
        space_infiltration_object.remove
        number_removed = number_removed +1
      elsif opt_space_type.get.spaces.size > 0
        space_infiltration_object.remove
        number_removed = number_removed +1
      else
        number_left = number_left +1
      end
    end
    if number_removed > 0
      runner.registerInfo("#{number_removed} design flow rate infiltration objects were removed.")
    end
    if number_left > 0
      runner.registerInfo("#{number_left} design flow rate infiltration objects in unused space types were left in the model. They will not be altered.")
    end    
    
    #add new infiltration to spaces 
    spaces = model.getSpaces
    spaces.each do |s|
      #only spaces connected to ambient
      if s.exteriorArea > 0 
        infiltration = OpenStudio::Model::SpaceInfiltrationDesignFlowRate.new(model)
        infiltration.setName("#{s.name.get} HVAC On Infiltration")
        #this also changes the calculation method to flow per exterior area
        infiltration.setFlowperExteriorSurfaceArea(ides);
        infiltration.setConstantTermCoefficient( aon )
        infiltration.setTemperatureTermCoefficient( bon )
        infiltration.setVelocityTermCoefficient( 0 )
        infiltration.setVelocitySquaredTermCoefficient( don )
        infiltration.setSpace( s )
        infiltration.setSchedule(on_schedule)
        # echo the new infiltration's name back to the user
        runner.registerInfo("Infiltration named #{infiltration.name.get} was added.")
        
        infiltration = OpenStudio::Model::SpaceInfiltrationDesignFlowRate.new(model)
        infiltration.setName("#{s.name.get} HVAC Off Infiltration")
        #this also changes the calculation method to flow per exterior area
        infiltration.setFlowperExteriorSurfaceArea(ides);
        infiltration.setConstantTermCoefficient( 0 )
        infiltration.setTemperatureTermCoefficient( boff )
        infiltration.setVelocityTermCoefficient( 0 )
        infiltration.setVelocitySquaredTermCoefficient( doff )
        infiltration.setSpace( s )
        infiltration.setSchedule(off_schedule)
        # echo the new infiltration's name back to the user
        runner.registerInfo("Infiltration named #{infiltration.name.get} was added.")
      end
    end

    return true

  end
  
end

# register the measure to be used by the application
Infiltration.new.registerWithApplication
