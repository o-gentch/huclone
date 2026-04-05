class PersonasController < ApplicationController
  def index
    persona = Persona.first
    if persona
      redirect_to persona_contents_path(persona)
    else
      render :index
    end
  end

  def new
    @persona = Persona.new
  end

  def create
    @persona = Persona.new(persona_params)
    if @persona.save
      redirect_to persona_contents_path(@persona)
    else
      render :new, status: :unprocessable_entity
    end
  end

  private

  def persona_params
    params.require(:persona).permit(:name, :system_prompt)
  end
end
