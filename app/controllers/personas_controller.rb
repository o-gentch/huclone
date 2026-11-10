class PersonasController < ApplicationController
  def index
    persona = Current.user.personas.order(:id).first
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
    @persona = Current.user.personas.new(persona_params)
    if @persona.save
      redirect_to persona_contents_path(@persona)
    else
      render :new, status: :unprocessable_entity
    end
  end

  def edit
    @persona = Current.user.personas.find(params[:id])
  end

  def update
    @persona = Current.user.personas.find(params[:id])
    if @persona.update(persona_params)
      redirect_to edit_persona_path(@persona), notice: "Сохранено"
    else
      render :edit, status: :unprocessable_entity
    end
  end

  # Удаляется только Digital Double: материалы остаются в библиотеке
  def destroy
    Current.user.personas.find(params[:id]).destroy
    redirect_to root_path, notice: "Персона удалена. Материалы остались в библиотеке"
  end

  def rebuild_portrait
    persona = Current.user.personas.find(params[:id])
    persona.reset_derived_knowledge!
    redirect_to edit_persona_path(persona), notice: "Портрет пересобирается — это займёт несколько минут"
  end

  private

  def persona_params
    params.require(:persona).permit(:name, :system_prompt)
  end
end
